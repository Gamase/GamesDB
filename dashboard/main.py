"""
GamesDB Dashboard - Backend
FastAPI + pyodbc  |  Puerto 8000
Ejecutar: uvicorn main:app --reload --host 0.0.0.0 --port 8000
"""

from fastapi import FastAPI
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import pyodbc
import json
from datetime import datetime
from decimal import Decimal
from typing import Optional

# ---------------------------------------------------------------------------
# Configuracion — ajusta SERVER si es necesario
# ---------------------------------------------------------------------------
SERVER   = r'DESKTOP-M1FKU4T\SQLDEV'
DATABASE = 'GamesDB'
BITACORA_DB = 'Bitacora_Central'

_DRIVERS = [
    'ODBC Driver 18 for SQL Server',
    'ODBC Driver 17 for SQL Server',
    'SQL Server',
]

# ---------------------------------------------------------------------------
app = FastAPI(title="GamesDB Dashboard API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# Conexion
# ---------------------------------------------------------------------------

def get_conn(database: str = DATABASE) -> pyodbc.Connection:
    available = pyodbc.drivers()
    driver = next((d for d in _DRIVERS if d in available), None)
    if driver is None:
        raise RuntimeError(f"No ODBC driver found. Available: {available}")
    conn_str = (
        f"DRIVER={{{driver}}};"
        f"SERVER={SERVER};"
        f"DATABASE={database};"
        f"Trusted_Connection=yes;"
        f"TrustServerCertificate=yes;"
    )
    return pyodbc.connect(conn_str, timeout=10)


def rows_to_dict(cursor: pyodbc.Cursor) -> list[dict]:
    cols = [c[0] for c in cursor.description]
    result = []
    for row in cursor.fetchall():
        d = {}
        for col, val in zip(cols, row):
            if isinstance(val, datetime):
                d[col] = val.isoformat()
            elif isinstance(val, Decimal):
                d[col] = float(val)
            else:
                d[col] = val
        result.append(d)
    return result


# ---------------------------------------------------------------------------
# ENDPOINTS
# ---------------------------------------------------------------------------

@app.get("/api/stats")
def get_stats():
    try:
        conn = get_conn()
        cur = conn.cursor()
        cur.execute("""
            SELECT
                COUNT(DISTINCT j.id_juego)                          AS total_juegos,
                COUNT(DISTINCT r.id_resena)                         AS juegos_con_resenas,
                SUM(u.jugadores_actuales)                           AS jugadores_actuales_total,
                CAST(AVG(CAST(u.jugadores_actuales AS FLOAT)) AS DECIMAL(12,0)) AS promedio_jugadores,
                CAST(AVG(r.porcentaje_positivo) AS DECIMAL(5,2))    AS rating_promedio_global,
                MAX(u.fecha_registro)                               AS ultima_actualizacion,
                COUNT(CASE WHEN CAST(j.fecha_creacion AS DATE) = CAST(SYSUTCDATETIME() AS DATE) THEN 1 END) AS juegos_nuevos_hoy
            FROM dbo.juegos j
            LEFT JOIN (
                SELECT id_juego, jugadores_actuales, fecha_registro,
                       ROW_NUMBER() OVER (PARTITION BY id_juego ORDER BY fecha_registro DESC) AS rn
                FROM dbo.estadisticas
            ) u ON u.id_juego = j.id_juego AND u.rn = 1
            LEFT JOIN dbo.resenas r ON r.id_juego = j.id_juego
        """)
        data = rows_to_dict(cur)
        conn.close()
        return JSONResponse(content={"ok": True, "data": data[0] if data else {}})
    except Exception as e:
        return JSONResponse(content={"ok": False, "error": str(e)}, status_code=500)


@app.get("/api/top_juegos")
def get_top_juegos(limit: int = 10):
    """Top juegos con jugadores actuales (ultimo snapshot)."""
    try:
        conn = get_conn()
        cur = conn.cursor()
        cur.execute("""
            SELECT TOP (?)
                j.nombre,
                j.steam_appid,
                j.desarrollador,
                j.precio,
                e.jugadores_actuales,
                e.jugadores_pico,
                r.porcentaje_positivo,
                r.descripcion_general,
                e.fecha_registro AS ultima_lectura
            FROM dbo.juegos j
            CROSS APPLY (
                SELECT TOP 1
                    jugadores_actuales,
                    jugadores_pico,
                    fecha_registro
                FROM dbo.estadisticas
                WHERE id_juego = j.id_juego
                ORDER BY fecha_registro DESC
            ) e
            LEFT JOIN dbo.resenas r ON r.id_juego = j.id_juego
            ORDER BY e.jugadores_actuales DESC
        """, limit)
        data = rows_to_dict(cur)
        conn.close()
        return JSONResponse(content={"ok": True, "data": data})
    except Exception as e:
        return JSONResponse(content={"ok": False, "error": str(e)}, status_code=500)


@app.get("/api/mirroring")
def get_mirroring():
    """Estado del mirroring de base de datos."""
    try:
        conn = get_conn("master")
        cur = conn.cursor()
        cur.execute("""
            SELECT
                db.name                             AS base_datos,
                dm.mirroring_state_desc             AS estado,
                dm.mirroring_role_desc              AS rol,
                dm.mirroring_partner_instance       AS partner,
                dm.mirroring_safety_level_desc      AS seguridad,
                dm.mirroring_witness_state_desc     AS testigo
            FROM sys.databases db
            JOIN sys.database_mirroring dm
                ON db.database_id = dm.database_id
            WHERE dm.mirroring_state IS NOT NULL
              AND db.name = N'GamesDB'
        """)
        data = rows_to_dict(cur)
        conn.close()
        return JSONResponse(content={"ok": True, "data": data})
    except Exception as e:
        return JSONResponse(content={"ok": False, "error": str(e)}, status_code=500)


@app.get("/api/linked_server")
def get_linked_server():
    """Prueba el linked server MySQL ejecutando una query simple."""
    try:
        conn = get_conn()
        cur = conn.cursor()
        # Verifica que el linked server exista
        cur.execute("""
            SELECT name, product, provider, data_source, is_linked
            FROM sys.servers
            WHERE is_linked = 1
        """)
        servers = rows_to_dict(cur)

        # Intenta query real al linked server MySQL
        mysql_ok = False
        mysql_version = None
        mysql_error = None
        try:
            cur.execute("SELECT * FROM OPENQUERY(MYSQL_GAMESDB, 'SELECT VERSION() AS v')")
            row = cur.fetchone()
            if row:
                mysql_ok = True
                mysql_version = row[0]
        except Exception as ex:
            mysql_error = str(ex)

        conn.close()
        return JSONResponse(content={
            "ok": True,
            "linked_servers": servers,
            "mysql_ping": {
                "ok": mysql_ok,
                "version": mysql_version,
                "error": mysql_error,
            }
        })
    except Exception as e:
        return JSONResponse(content={"ok": False, "error": str(e)}, status_code=500)


@app.get("/api/bitacora")
def get_bitacora(limit: int = 20):
    """Ultimos registros de la bitacora JSON."""
    try:
        conn = get_conn(BITACORA_DB)
        cur = conn.cursor()
        cur.execute("""
            SELECT TOP (?)
                id_bitacora,
                base_datos,
                tabla,
                operacion,
                fecha,
                usuario,
                campos_cambiados
            FROM dbo.bitacora
            ORDER BY fecha DESC
        """, limit)
        data = rows_to_dict(cur)
        conn.close()
        return JSONResponse(content={"ok": True, "data": data})
    except Exception as e:
        return JSONResponse(content={"ok": False, "error": str(e)}, status_code=500)


@app.get("/api/generos")
def get_generos():
    """Juegos y rating promedio por genero (top 10)."""
    try:
        conn = get_conn()
        cur = conn.cursor()
        cur.execute("""
            SELECT TOP 10
                genero,
                cantidad_juegos,
                precio_promedio,
                rating_promedio
            FROM dbo.vw_juegos_por_genero
            ORDER BY cantidad_juegos DESC
        """)
        data = rows_to_dict(cur)
        conn.close()
        return JSONResponse(content={"ok": True, "data": data})
    except Exception as e:
        return JSONResponse(content={"ok": False, "error": str(e)}, status_code=500)


# ---------------------------------------------------------------------------
# Frontend — sirve el HTML
# ---------------------------------------------------------------------------

@app.get("/", response_class=HTMLResponse)
def index():
    with open("index.html", "r", encoding="utf-8") as f:
        return f.read()


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
