"""
sync_mysql.py — Sincroniza GamesDB de SQL Server hacia MySQL.

Uso:
    python sync_mysql.py [--modo FULL|INCREMENTAL]

Dependencias:
    pip install pyodbc mysql-connector-python
"""

import argparse
import sys
import pyodbc
import mysql.connector
from mysql.connector import Error as MySQLError

# ---------------------------------------------------------------------------
# Configuracion de conexiones
# ---------------------------------------------------------------------------

SS_SERVER   = r"DESKTOP-M1FKU4T\SQLDEV"
SS_DATABASE = "GamesDB"

MYSQL_CONFIG = {
    "host":     "100.123.151.3",
    "port":     3306,
    "user":     "gamesdb_user",
    "password": "Games2025!",
    "database": "gamesdb",
}

BATCH_SIZE = 500   # filas por lote en executemany


# ---------------------------------------------------------------------------
# Helpers de conexion
# ---------------------------------------------------------------------------

def conectar_sqlserver():
    for driver in ("ODBC Driver 18 for SQL Server", "ODBC Driver 17 for SQL Server"):
        try:
            conn = pyodbc.connect(
                f"DRIVER={{{driver}}};"
                f"SERVER={SS_SERVER};"
                f"DATABASE={SS_DATABASE};"
                "Trusted_Connection=yes;"
                "TrustServerCertificate=yes;"
            )
            print(f"[SQL Server] Conectado ({driver})")
            return conn
        except pyodbc.Error:
            continue
    raise RuntimeError("No se pudo conectar a SQL Server con ODBC 17 ni 18.")


def conectar_mysql():
    conn = mysql.connector.connect(**MYSQL_CONFIG)
    print(f"[MySQL] Conectado a {MYSQL_CONFIG['host']}:{MYSQL_CONFIG['port']}/{MYSQL_CONFIG['database']}")
    return conn


# ---------------------------------------------------------------------------
# Insercion por lotes
# ---------------------------------------------------------------------------

def insertar_lotes(my_cur, my_conn, sql, datos):
    """Ejecuta executemany en lotes de BATCH_SIZE; devuelve total de filas afectadas."""
    total = 0
    for i in range(0, len(datos), BATCH_SIZE):
        lote = datos[i : i + BATCH_SIZE]
        my_cur.executemany(sql, lote)
        total += my_cur.rowcount
    my_conn.commit()
    return total


# ---------------------------------------------------------------------------
# Truncado para modo FULL
# ---------------------------------------------------------------------------

TABLAS_TRUNCATE = [
    "estadisticas",   # depende de juegos
    "resenas",        # depende de juegos
    "juegos_generos", # depende de juegos y generos
    "juegos",
    "generos",
]


def truncar_tablas(my_cur, my_conn):
    print("\n[FULL] Truncando tablas en MySQL...")
    my_cur.execute("SET FOREIGN_KEY_CHECKS = 0")
    for tabla in TABLAS_TRUNCATE:
        my_cur.execute(f"TRUNCATE TABLE {tabla}")
        print(f"  TRUNCATE {tabla}")
    my_cur.execute("SET FOREIGN_KEY_CHECKS = 1")
    my_conn.commit()
    print("[FULL] Truncado completado.")


# ---------------------------------------------------------------------------
# Sincronizacion por tabla
# ---------------------------------------------------------------------------

def sync_generos(ss_cur, my_conn, my_cur, modo):
    print("\n[generos] Sincronizando...", end=" ", flush=True)

    if modo == "INCREMENTAL":
        my_cur.execute("SELECT COALESCE(MAX(id_genero), 0) FROM generos")
        max_id = my_cur.fetchone()[0]
        ss_cur.execute(
            "SELECT id_genero, nombre FROM generos WHERE id_genero > ?", max_id
        )
    else:
        ss_cur.execute("SELECT id_genero, nombre FROM generos")

    filas = ss_cur.fetchall()
    if not filas:
        print("sin cambios.")
        return 0

    sql = "INSERT IGNORE INTO generos (id_genero, nombre) VALUES (%s, %s)"
    datos = [(r.id_genero, r.nombre) for r in filas]
    n = insertar_lotes(my_cur, my_conn, sql, datos)
    print(f"{n} insertados de {len(filas)} procesados.")
    return n


def sync_juegos(ss_cur, my_conn, my_cur, modo):
    print("\n[juegos] Sincronizando...", end=" ", flush=True)

    base_sql = """
        SELECT id_juego, steam_appid, nombre, descripcion, precio,
               fecha_lanzamiento, desarrollador, publicador,
               fecha_creacion, fecha_actualizacion
        FROM juegos
    """
    if modo == "INCREMENTAL":
        my_cur.execute("SELECT COALESCE(MAX(id_juego), 0) FROM juegos")
        max_id = my_cur.fetchone()[0]
        ss_cur.execute(base_sql + " WHERE id_juego > ?", max_id)
    else:
        ss_cur.execute(base_sql)

    filas = ss_cur.fetchall()
    if not filas:
        print("sin cambios.")
        return 0

    sql = """
        INSERT INTO juegos
            (id_juego, steam_appid, nombre, descripcion, precio,
             fecha_lanzamiento, desarrollador, publicador,
             fecha_creacion, fecha_actualizacion)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        ON DUPLICATE KEY UPDATE
            nombre              = VALUES(nombre),
            descripcion         = VALUES(descripcion),
            precio              = VALUES(precio),
            fecha_lanzamiento   = VALUES(fecha_lanzamiento),
            desarrollador       = VALUES(desarrollador),
            publicador          = VALUES(publicador),
            fecha_actualizacion = VALUES(fecha_actualizacion)
    """
    datos = [
        (
            r.id_juego, r.steam_appid, r.nombre, r.descripcion,
            float(r.precio), r.fecha_lanzamiento, r.desarrollador,
            r.publicador, r.fecha_creacion, r.fecha_actualizacion,
        )
        for r in filas
    ]
    n = insertar_lotes(my_cur, my_conn, sql, datos)
    print(f"{n} insertados/actualizados de {len(filas)} procesados.")
    return n


def sync_juegos_generos(ss_cur, my_conn, my_cur, modo):
    print("\n[juegos_generos] Sincronizando...", end=" ", flush=True)

    if modo == "INCREMENTAL":
        # Solo pares cuyo id_juego sea nuevo en MySQL
        my_cur.execute("SELECT COALESCE(MAX(id_juego), 0) FROM juegos_generos")
        max_jg = my_cur.fetchone()[0]
        ss_cur.execute(
            "SELECT id_juego, id_genero FROM juegos_generos WHERE id_juego > ?",
            max_jg,
        )
    else:
        ss_cur.execute("SELECT id_juego, id_genero FROM juegos_generos")

    filas = ss_cur.fetchall()
    if not filas:
        print("sin cambios.")
        return 0

    sql = "INSERT IGNORE INTO juegos_generos (id_juego, id_genero) VALUES (%s, %s)"
    datos = [(r.id_juego, r.id_genero) for r in filas]
    n = insertar_lotes(my_cur, my_conn, sql, datos)
    print(f"{n} insertados de {len(filas)} procesados.")
    return n


def sync_resenas(ss_cur, my_conn, my_cur, modo):
    print("\n[resenas] Sincronizando...", end=" ", flush=True)

    base_sql = """
        SELECT id_resena, id_juego, positivas, negativas,
               porcentaje_positivo, descripcion_general
        FROM resenas
    """
    if modo == "INCREMENTAL":
        my_cur.execute("SELECT COALESCE(MAX(id_resena), 0) FROM resenas")
        max_id = my_cur.fetchone()[0]
        ss_cur.execute(base_sql + " WHERE id_resena > ?", max_id)
    else:
        ss_cur.execute(base_sql)

    filas = ss_cur.fetchall()
    if not filas:
        print("sin cambios.")
        return 0

    sql = """
        INSERT INTO resenas
            (id_resena, id_juego, positivas, negativas,
             porcentaje_positivo, descripcion_general)
        VALUES (%s, %s, %s, %s, %s, %s)
        ON DUPLICATE KEY UPDATE
            positivas           = VALUES(positivas),
            negativas           = VALUES(negativas),
            porcentaje_positivo = VALUES(porcentaje_positivo),
            descripcion_general = VALUES(descripcion_general)
    """
    datos = [
        (
            r.id_resena, r.id_juego, r.positivas, r.negativas,
            float(r.porcentaje_positivo), r.descripcion_general,
        )
        for r in filas
    ]
    n = insertar_lotes(my_cur, my_conn, sql, datos)
    print(f"{n} insertados/actualizados de {len(filas)} procesados.")
    return n


def sync_estadisticas(ss_cur, my_conn, my_cur, modo):
    """
    Estadisticas solo acepta registros nuevos (append-only).
    Se compara MAX(id_estadistica) en ambas bases para determinar
    desde donde continuar, ignorando el modo FULL/INCREMENTAL.
    """
    print("\n[estadisticas] Sincronizando...", end=" ", flush=True)

    my_cur.execute("SELECT COALESCE(MAX(id_estadistica), 0) FROM estadisticas")
    max_my = my_cur.fetchone()[0]

    ss_cur.execute("SELECT COALESCE(MAX(id_estadistica), 0) FROM estadisticas")
    max_ss = ss_cur.fetchone()[0]

    if max_my >= max_ss:
        print(f"sin cambios (max id MySQL={max_my}, SQL Server={max_ss}).")
        return 0

    ss_cur.execute(
        """
        SELECT id_estadistica, id_juego, jugadores_actuales,
               jugadores_pico, total_resenas, fecha_registro
        FROM estadisticas
        WHERE id_estadistica > ?
        ORDER BY id_estadistica
        """,
        max_my,
    )
    filas = ss_cur.fetchall()
    if not filas:
        print("sin cambios.")
        return 0

    sql = """
        INSERT INTO estadisticas
            (id_estadistica, id_juego, jugadores_actuales,
             jugadores_pico, total_resenas, fecha_registro)
        VALUES (%s, %s, %s, %s, %s, %s)
    """
    datos = [
        (
            r.id_estadistica, r.id_juego, r.jugadores_actuales,
            r.jugadores_pico, r.total_resenas, r.fecha_registro,
        )
        for r in filas
    ]
    n = insertar_lotes(my_cur, my_conn, sql, datos)
    print(f"{n} registros nuevos insertados.")
    return n


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Sincroniza GamesDB de SQL Server hacia MySQL."
    )
    parser.add_argument(
        "--modo",
        choices=["FULL", "INCREMENTAL"],
        default="INCREMENTAL",
        help="FULL: sincroniza todo | INCREMENTAL: solo lo nuevo (default)",
    )
    args = parser.parse_args()

    print(f"{'='*55}")
    print(f"  Sincronizacion GamesDB  |  Modo: {args.modo}")
    print(f"{'='*55}")

    ss_conn = None
    my_conn = None

    try:
        ss_conn = conectar_sqlserver()
        my_conn = conectar_mysql()

        ss_cur = ss_conn.cursor()
        my_cur = my_conn.cursor()

        if args.modo == "FULL":
            truncar_tablas(my_cur, my_conn)

        total = 0
        total += sync_generos(ss_cur, my_conn, my_cur, args.modo)
        total += sync_juegos(ss_cur, my_conn, my_cur, args.modo)
        total += sync_juegos_generos(ss_cur, my_conn, my_cur, args.modo)
        total += sync_resenas(ss_cur, my_conn, my_cur, args.modo)
        total += sync_estadisticas(ss_cur, my_conn, my_cur, args.modo)

        print(f"\n{'='*55}")
        print(f"  Sincronizacion completada. Operaciones totales: {total}")
        print(f"{'='*55}\n")

    except (pyodbc.Error, MySQLError, RuntimeError) as exc:
        print(f"\n[ERROR] {exc}", file=sys.stderr)
        if my_conn and my_conn.is_connected():
            my_conn.rollback()
            print("[MySQL] Rollback ejecutado.", file=sys.stderr)
        sys.exit(1)

    finally:
        if ss_conn:
            ss_conn.close()
        if my_conn and my_conn.is_connected():
            my_conn.close()
        print("Conexiones cerradas.")


if __name__ == "__main__":
    main()
