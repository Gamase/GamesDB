[README_github.md](https://github.com/user-attachments/files/27789556/README_github.md)
# GamesDB — Steam Analytics Platform

A distributed database system that fetches real-time Steam player data, stores it across multiple database engines, and exposes it through a live web dashboard.

![SQL Server](https://img.shields.io/badge/SQL%20Server-2019-CC2927?style=flat&logo=microsoftsqlserver)
![MySQL](https://img.shields.io/badge/MySQL-8.0-4479A1?style=flat&logo=mysql&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.14-3776AB?style=flat&logo=python&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-0.115-009688?style=flat&logo=fastapi&logoColor=white)
![Tailscale](https://img.shields.io/badge/Tailscale-VPN-243556?style=flat&logo=tailscale)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Tailscale VPN                        │
│                                                             │
│  ┌──────────────────┐        ┌──────────────────────────┐  │
│  │  Laptop (Main)   │        │     PC Casa (Mirror)     │  │
│  │  SQL Server 2019 │◄──────►│     SQL Server 2019      │  │
│  │  DESKTOP-M1FKU4T │Mirror  │     Gamase\SQLMIRROR     │  │
│  └────────┬─────────┘        └──────────────────────────┘  │
│           │ Linked Server                                   │
│           │                                                 │
│  ┌────────▼─────────┐                                      │
│  │  Nintendo Switch │                                      │
│  │  KUbuntu Linux   │                                      │
│  │  MySQL 8.0.45    │                                      │
│  └──────────────────┘                                      │
└─────────────────────────────────────────────────────────────┘

Steam API ──► steam_loader.py ──► SQL Server ──► Dashboard
                (every 5 min)                  (FastAPI + HTML)
```

---

## Features

- **Real-time Steam data** — Fetches top 100 most-played games every 5 minutes via Steam Web API
- **Distributed storage** — SQL Server as primary, MySQL on Nintendo Switch as secondary node
- **High availability** — SQL Server Database Mirroring with automatic failover
- **Cross-engine sync** — `sync_mysql.py` synchronizes all tables from SQL Server to MySQL
- **Audit trail** — JSON audit triggers logging every INSERT/UPDATE/DELETE to a separate `Bitacora_Central` database
- **Automated backups** — SQL Agent jobs: FULL daily, differential every 6h, log every 30min
- **Live dashboard** — FastAPI backend + vanilla JS frontend with auto-refresh every 30 seconds
- **VPN mesh** — All 3 nodes connected via Tailscale regardless of physical network

---

## Database Schema

```
juegos          — Master game data (steam_appid, name, price, developer)
estadisticas    — Append-only player count snapshots (time series)
resenas         — Review scores (positive %, description)
generos         — Game genres
juegos_generos  — N:M relationship between games and genres
```

### Database Objects

| Object | Type | Purpose |
|--------|------|---------|
| `vw_top_juegos` | View | Top games with peak players, genres, and ratings joined |
| `vw_juegos_por_genero` | View | Game count, avg price and rating per genre |
| `vw_mejores_resenas` | View | Games with >90% positive reviews |
| `tvf_juegos_por_precio` | TVF | Parameterized filter by price range — composable in SELECT |
| `tvf_juegos_por_rating` | TVF | Parameterized filter by minimum rating |
| `tvf_estadisticas_por_juego` | TVF | Player history with LAG-based deltas per game |
| `sp_reporte_diario` | SP | 4 result sets: summary, top 5, top genres, biggest movers |
| `sp_sincronizar_mysql` | SP | Linked server sync (FULL/INCREMENTAL) via MSDASQL |
| `sp_backup_full` | SP | Full database backup with COMPRESSION + CHECKSUM |
| `sp_backup_differential` | SP | Differential backup |
| `sp_backup_log` | SP | Transaction log backup |

> **Why TVFs over SPs for parameterized queries?**  
> TVFs are composable — you can use them inside SELECT, JOIN, or WHERE clauses. A stored procedure returns result sets that cannot be used within another query.

---

## Project Structure

```
GamesDB/
├── python/
│   ├── steam_loader.py        # Fetches Steam API data → SQL Server
│   ├── steam_scheduler.py     # Runs steam_loader every 5 minutes
│   ├── sync_mysql.py          # Syncs SQL Server → MySQL (bypasses MSDASQL)
│   └── iniciar_scheduler.bat  # Windows launcher (background, no console)
│
├── sql/
│   ├── 01_crear_gamesdb.sql         # Schema: tables, indexes, constraints
│   ├── 02_vistas_tvf_sp.sql         # Views, TVFs, stored procedures
│   ├── 03_triggers_bitacora.sql     # Audit triggers + Bitacora_Central DB
│   ├── 04_backups.sql               # Backup SPs + SQL Agent jobs
│   └── 06_job_sincronizar_mysql.sql # MySQL sync job + linked server setup
│
└── dashboard/
    ├── main.py           # FastAPI backend (API endpoints + serves HTML)
    ├── index.html        # Frontend (HTML + CSS + Chart.js + vanilla JS)
    └── requirements.txt  # Python dependencies
```

---

## Getting Started

### Prerequisites

- SQL Server 2019+ with SQL Server Agent enabled
- Python 3.9+
- MySQL 8.0 on secondary node
- Tailscale installed on all nodes
- ODBC Driver 17 or 18 for SQL Server
- MySQL ODBC 9.x Driver

### 1. Database Setup

Run the SQL scripts in order against your SQL Server instance:

```sql
-- 1. Create database and schema
-- Run: sql/01_crear_gamesdb.sql

-- 2. Create views, TVFs, and stored procedures
-- Run: sql/02_vistas_tvf_sp.sql

-- 3. Create audit triggers and Bitacora_Central
-- Run: sql/03_triggers_bitacora.sql

-- 4. Create backup stored procedures and SQL Agent jobs
-- Run: sql/04_backups.sql

-- 5. Configure linked server and MySQL sync job
-- Run: sql/06_job_sincronizar_mysql.sql
```

### 2. Python Dependencies

```bash
pip install pyodbc requests fastapi uvicorn mysql-connector-python
```

### 3. Start the Steam Loader

```bash
# Run once
python python/steam_loader.py

# Run continuously every 5 minutes
python python/steam_scheduler.py

# Or use the Windows launcher (runs in background)
iniciar_scheduler.bat
```

### 4. Sync to MySQL

```bash
# First time — full sync
python python/sync_mysql.py --modo FULL

# Subsequent runs — incremental only
python python/sync_mysql.py --modo INCREMENTAL
```

### 5. Start the Dashboard

```bash
cd dashboard
python -m uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

Open in browser: `http://localhost:8000`

---

## Dashboard

The dashboard auto-refreshes every 30 seconds and shows:

- **Stats** — Total games, online players, global rating, last load time
- **Top Games** — Real-time player counts, peak, price, and review score
- **Infrastructure Status** — SQL Server, Mirroring, MySQL Linked Server, Audit DB, Steam Loader
- **Genre Chart** — Game count and avg rating per genre (Chart.js)
- **Audit Log** — Last 20 changes from `Bitacora_Central` with operation type and changed fields

---

## Mirroring & Failover

```sql
-- Check mirroring status
SELECT db.name, dm.mirroring_state_desc, dm.mirroring_role_desc
FROM sys.databases db
JOIN sys.database_mirroring dm ON db.database_id = dm.database_id
WHERE db.name = 'GamesDB';

-- Manual failover (run on the mirror node)
ALTER DATABASE GamesDB SET PARTNER FAILOVER;
```

---

## Backup Strategy

| Job | Schedule | Type |
|-----|----------|------|
| GamesDB - Backup Full | Daily 2:00 AM | Full + COMPRESSION + CHECKSUM |
| GamesDB - Backup Diferencial | Every 6 hours | Differential |
| GamesDB - Backup Log | Every 30 minutes | Transaction Log |
| GamesDB - Limpiar Backups | Daily 3:00 AM | Deletes files older than 7 days |

**Maximum recovery point:** 30 minutes of data loss.

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Primary DB | Microsoft SQL Server 2019 |
| Secondary DB | MySQL 8.0 on KUbuntu (Nintendo Switch) |
| VPN | Tailscale (mesh, peer-to-peer) |
| Data ingestion | Python 3.14 + pyodbc + requests |
| MySQL sync | Python + mysql-connector-python |
| API | FastAPI + Uvicorn |
| Frontend | HTML5 + CSS3 + Vanilla JS + Chart.js |
| Replication | SQL Server Database Mirroring |
| Cross-engine | SQL Server Linked Server (MSDASQL) |

---

## Steam APIs Used

| API | Data |
|-----|------|
| `ISteamChartsService/GetMostPlayedGames` | Top 100 ranking |
| `store.steampowered.com/api/appdetails` | Name, price, genres, developer |
| `store.steampowered.com/appreviews` | Review scores |
| `ISteamUserStats/GetNumberOfCurrentPlayers` | Real-time player count |

---

## Security Notes

- Audit triggers run as `usr_escritura` — a restricted login with INSERT-only access to `Bitacora_Central`
- `usr_lectura` has SELECT-only access — cannot modify or delete audit records
- Database mirroring uses certificate-based authentication (no domain required)
- Passwords and sensitive config should be moved to environment variables before production use

---

## Author

**Sebastian** — [@Gamase](https://github.com/Gamase)  
*Database Administration Project*
