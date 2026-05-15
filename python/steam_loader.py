#!/usr/bin/env python3
"""
steam_loader.py
Carga los top 100 juegos mas jugados de Steam en GamesDB (SQL Server).

Dependencias:  pip install pyodbc requests
"""

import sys
import time
import logging
from datetime import datetime, date
from typing import Dict, List, Optional, Any

import pyodbc
import requests

# ---------------------------------------------------------------------------
# Configuracion
# ---------------------------------------------------------------------------
SERVER   = r'DESKTOP-M1FKU4T\SQLDEV'
DATABASE = 'GamesDB'

# Intenta driver 17 y 18 segun lo que este instalado
_DRIVERS = [
    'ODBC Driver 18 for SQL Server',
    'ODBC Driver 17 for SQL Server',
    'SQL Server',
]

TOP_N           = 100
REQUEST_DELAY   = 1.5   # segundos entre llamadas (evita 429 del Store API)
REQUEST_TIMEOUT = 15

CHARTS_URL  = 'https://api.steampowered.com/ISteamChartsService/GetMostPlayedGames/v1/'
PLAYERS_URL = 'https://api.steampowered.com/ISteamUserStats/GetNumberOfCurrentPlayers/v1/'
DETAILS_URL = 'https://store.steampowered.com/api/appdetails'
REVIEWS_URL = 'https://store.steampowered.com/appreviews/{appid}'

# ---------------------------------------------------------------------------
# Logging  (consola + archivo)
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s  %(levelname)-8s  %(message)s',
    datefmt='%H:%M:%S',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler('steam_loader.log', encoding='utf-8'),
    ],
)
log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Parseo de fecha Steam  ("May 13, 2020", "13 May, 2020", "2020", …)
# ---------------------------------------------------------------------------
_DATE_FMTS = (
    '%b %d, %Y', '%d %b, %Y',
    '%B %d, %Y', '%d %B, %Y',
    '%Y-%m-%d',  '%Y',
)

def _parse_date(raw: str) -> Optional[date]:
    for fmt in _DATE_FMTS:
        try:
            return datetime.strptime(raw.strip(), fmt).date()
        except ValueError:
            pass
    return None   # "Coming Soon", "Q1 2025", strings vacios, etc.

# ---------------------------------------------------------------------------
# Steam API
# ---------------------------------------------------------------------------
_http = requests.Session()
_http.headers['Accept-Language'] = 'en-US,en;q=0.9'


def _get(url: str, params: Optional[Dict] = None, retries: int = 2) -> Optional[Dict]:
    for attempt in range(retries + 1):
        try:
            r = _http.get(url, params=params, timeout=REQUEST_TIMEOUT)
            if r.status_code == 429:
                wait = 30 * (attempt + 1)
                log.warning('Rate limit (429). Esperando %ds...', wait)
                time.sleep(wait)
                continue
            r.raise_for_status()
            return r.json()
        except requests.RequestException as exc:
            if attempt == retries:
                log.warning('HTTP error  %s  —  %s', url, exc)
            else:
                time.sleep(5)
    return None


def fetch_top_games(n: int = TOP_N) -> List[Dict[str, Any]]:
    """Top N juegos con jugadores_actuales y pico (ultimas 48 h)."""
    data = _get(CHARTS_URL)
    if not data:
        return []
    ranks = data.get('response', {}).get('ranks', [])[:n]
    return [
        {
            'steam_appid':        int(e['appid']),
            'jugadores_actuales': int(e.get('concurrent_in_game', 0)),
            'jugadores_pico':     int(e.get('peak_in_game', 0)),
        }
        for e in ranks
    ]


def fetch_details(appid: int) -> Optional[Dict[str, Any]]:
    """Nombre, descripcion, precio, fecha, dev, pub y generos de un juego."""
    data = _get(DETAILS_URL, params={'appids': appid, 'cc': 'us', 'l': 'english'})
    if not data:
        return None
    entry = data.get(str(appid), {})
    if not entry.get('success'):
        return None

    info = entry.get('data', {})
    price_overview = info.get('price_overview') or {}
    precio = round(price_overview.get('final', 0) / 100, 2) if price_overview else 0.00

    return {
        'nombre':            (info.get('name') or '').strip(),
        'descripcion':       info.get('short_description') or '',
        'precio':            precio,
        'fecha_lanzamiento': _parse_date(info.get('release_date', {}).get('date', '')),
        'desarrollador':     ', '.join(info.get('developers', [])) or None,
        'publicador':        ', '.join(info.get('publishers', [])) or None,
        'generos':           [g['description'] for g in info.get('genres', [])],
    }


def fetch_reviews(appid: int) -> Optional[Dict[str, Any]]:
    """Total positivas, negativas y descripcion general de resenas."""
    data = _get(
        REVIEWS_URL.format(appid=appid),
        params={'json': 1, 'language': 'all', 'purchase_type': 'all', 'num_per_page': 0},
    )
    if not data or data.get('success') != 1:
        return None
    s = data.get('query_summary', {})
    return {
        'positivas':           int(s.get('total_positive', 0)),
        'negativas':           int(s.get('total_negative', 0)),
        'descripcion_general': s.get('review_score_desc') or None,
    }


def fetch_jugadores_actuales(appid: int) -> Optional[int]:
    """
    Jugadores en tiempo real via ISteamUserStats/GetNumberOfCurrentPlayers.
    Mas fresco que concurrent_in_game del ranking (que se captura una vez
    al inicio y puede tener minutos de retraso para los ultimos juegos).
    No requiere API key. Devuelve None si la llamada falla.
    """
    data = _get(PLAYERS_URL, params={'appid': appid})
    if not data:
        return None
    resp = data.get('response', {})
    if resp.get('result') != 1:
        return None
    return int(resp.get('player_count', 0))

# ---------------------------------------------------------------------------
# SQL Server — conexion
# ---------------------------------------------------------------------------
_VALID_DESC = {
    'Overwhelmingly Positive', 'Very Positive', 'Positive', 'Mostly Positive',
    'Mixed', 'Mostly Negative', 'Negative', 'Very Negative', 'Overwhelmingly Negative',
}

def get_connection() -> pyodbc.Connection:
    available = pyodbc.drivers()
    driver = next((d for d in _DRIVERS if d in available), None)
    if driver is None:
        raise RuntimeError(
            f'No se encontro un driver ODBC de SQL Server. '
            f'Disponibles: {available}'
        )
    log.info('Usando driver: %s', driver)
    conn_str = (
        f'DRIVER={{{driver}}};'
        f'SERVER={SERVER};'
        f'DATABASE={DATABASE};'
        f'Trusted_Connection=yes;'
        f'TrustServerCertificate=yes;'
    )
    return pyodbc.connect(conn_str, autocommit=False, timeout=30)

# ---------------------------------------------------------------------------
# SQL Server — operaciones de escritura
# ---------------------------------------------------------------------------
_SQL_UPDATE_JUEGO = """
UPDATE juegos
SET nombre              = ?,
    descripcion         = ?,
    precio              = ?,
    fecha_lanzamiento   = ?,
    desarrollador       = ?,
    publicador          = ?,
    fecha_actualizacion = SYSUTCDATETIME()
WHERE steam_appid = ?
"""

_SQL_INSERT_JUEGO = """
INSERT INTO juegos
    (steam_appid, nombre, descripcion, precio,
     fecha_lanzamiento, desarrollador, publicador)
VALUES (?, ?, ?, ?, ?, ?, ?)
"""


def upsert_juego(cur: pyodbc.Cursor, appid: int, det: Dict) -> int:
    nombre = det['nombre'][:255]
    cur.execute(_SQL_UPDATE_JUEGO, (
        nombre, det['descripcion'], det['precio'],
        det['fecha_lanzamiento'], det['desarrollador'], det['publicador'],
        appid,
    ))
    if cur.rowcount == 0:
        cur.execute(_SQL_INSERT_JUEGO, (
            appid, nombre, det['descripcion'], det['precio'],
            det['fecha_lanzamiento'], det['desarrollador'], det['publicador'],
        ))
    cur.execute('SELECT id_juego FROM juegos WHERE steam_appid = ?', (appid,))
    return int(cur.fetchone()[0])


def get_or_create_genero(cur: pyodbc.Cursor, nombre: str) -> int:
    nombre = nombre[:100]
    cur.execute('SELECT id_genero FROM generos WHERE nombre = ?', (nombre,))
    row = cur.fetchone()
    if row:
        return int(row[0])
    cur.execute(
        'INSERT INTO generos (nombre) OUTPUT inserted.id_genero VALUES (?)',
        (nombre,),
    )
    return int(cur.fetchone()[0])


def sync_generos(cur: pyodbc.Cursor, id_juego: int, nombres: List[str]) -> None:
    cur.execute('DELETE FROM juegos_generos WHERE id_juego = ?', (id_juego,))
    for nombre in nombres:
        gid = get_or_create_genero(cur, nombre)
        cur.execute(
            'INSERT INTO juegos_generos (id_juego, id_genero) VALUES (?, ?)',
            (id_juego, gid),
        )


def insert_estadisticas(cur: pyodbc.Cursor, id_juego: int, stats: Dict) -> None:
    actuales = stats['jugadores_actuales']
    pico     = max(stats['jugadores_pico'], actuales)   # invariante del CHECK constraint
    cur.execute(
        'INSERT INTO estadisticas (id_juego, jugadores_actuales, jugadores_pico, total_resenas) '
        'VALUES (?, ?, ?, ?)',
        (id_juego, actuales, pico, stats['total_resenas']),
    )


_MERGE_RESENA = """
MERGE resenas WITH (HOLDLOCK) AS tgt
USING (VALUES (?)) AS src (id_juego)
ON tgt.id_juego = src.id_juego
WHEN MATCHED THEN
    UPDATE SET positivas           = ?,
               negativas           = ?,
               porcentaje_positivo = ?,
               descripcion_general = ?
WHEN NOT MATCHED THEN
    INSERT (id_juego, positivas, negativas, porcentaje_positivo, descripcion_general)
    VALUES (?,        ?,         ?,         ?,                   ?);
"""


def upsert_resena(cur: pyodbc.Cursor, id_juego: int, rev: Dict) -> None:
    pos   = rev['positivas']
    neg   = rev['negativas']
    total = pos + neg
    pct   = round(pos / total * 100, 2) if total > 0 else 0.00
    desc  = rev['descripcion_general'] if rev['descripcion_general'] in _VALID_DESC else None

    cur.execute(_MERGE_RESENA,
                (id_juego,
                 pos, neg, pct, desc,           # UPDATE
                 id_juego, pos, neg, pct, desc)) # INSERT

# ---------------------------------------------------------------------------
# Barra de progreso
# ---------------------------------------------------------------------------

def _progress(current: int, total: int, label: str = '') -> None:
    pct   = current / total
    width = 35
    done  = int(width * pct)
    bar   = '#' * done + '-' * (width - done)
    label = label[:42].ljust(42)
    print(f'\r  [{bar}] {current:>3}/{total}  {label}', end='', flush=True)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    log.info('=== steam_loader  inicio  %s ===', datetime.now().strftime('%Y-%m-%d %H:%M'))

    # 1. Ranking Steam
    log.info('Solicitando top %d juegos...', TOP_N)
    top_games = fetch_top_games(TOP_N)
    if not top_games:
        log.error('No se pudo obtener el ranking de Steam. Revisa la conexion.')
        sys.exit(1)
    log.info('Ranking recibido: %d juegos', len(top_games))

    # 2. Conexion SQL Server
    try:
        conn = get_connection()
    except Exception as exc:
        log.error('Conexion fallida: %s', exc)
        sys.exit(1)
    log.info('Conectado a [%s].[%s]', SERVER, DATABASE)
    log.info('Iniciando carga...\n')

    ok = skipped = errors = 0

    for i, entry in enumerate(top_games, start=1):
        appid = entry['steam_appid']
        _progress(i, len(top_games), f'appid={appid}')

        # -- Detalles --
        details = fetch_details(appid)
        time.sleep(REQUEST_DELAY)

        if not details or not details['nombre']:
            log.warning('\n[%d/%d] appid=%d sin detalles (DLC / app eliminada)', i, len(top_games), appid)
            skipped += 1
            continue

        nombre = details['nombre']

        # -- Resenas --
        reviews = fetch_reviews(appid)
        time.sleep(REQUEST_DELAY)
        total_resenas = (reviews['positivas'] + reviews['negativas']) if reviews else 0

        # -- Jugadores en tiempo real --
        # GetNumberOfCurrentPlayers es un endpoint ligero; delay reducido.
        # Si falla, se usa concurrent_in_game del ranking como fallback.
        actuales_rt = fetch_jugadores_actuales(appid)
        time.sleep(0.5)
        jugadores_actuales = actuales_rt if actuales_rt is not None else entry['jugadores_actuales']

        stats = {
            'jugadores_actuales': jugadores_actuales,
            'jugadores_pico':     max(entry['jugadores_pico'], jugadores_actuales),
            'total_resenas':      total_resenas,
        }

        # -- Escritura en DB (una transaccion por juego) --
        try:
            cur = conn.cursor()

            id_juego = upsert_juego(cur, appid, details)
            sync_generos(cur, id_juego, details['generos'])
            insert_estadisticas(cur, id_juego, stats)
            if reviews:
                upsert_resena(cur, id_juego, reviews)

            conn.commit()
            ok += 1
            log.debug('\n  [OK] id=%d  appid=%d  "%s"  jugadores=%d%s',
                      id_juego, appid, nombre, jugadores_actuales,
                      '' if actuales_rt is not None else ' (fallback)')

        except pyodbc.Error as exc:
            conn.rollback()
            errors += 1
            log.error('\n[%d/%d] DB error  appid=%d  "%s"\n  -> %s',
                      i, len(top_games), appid, nombre, exc)

    print()  # cierra la barra de progreso
    conn.close()

    log.info('')
    log.info('=== Resultado final ===')
    log.info('  Insertados/actualizados : %d', ok)
    log.info('  Omitidos (sin datos)    : %d', skipped)
    log.info('  Errores de base de datos: %d', errors)
    log.info('======================')


if __name__ == '__main__':
    main()
