# GamesDB Dashboard

Dashboard web en tiempo real para GamesDB Steam.

## Estructura

```
gamesdb_dashboard/
├── main.py           ← Backend FastAPI (API + sirve el HTML)
├── index.html        ← Frontend (HTML + CSS + JS vanilla)
├── requirements.txt  ← Dependencias Python
└── README.md
```

## Instalación (una sola vez)

```bash
cd C:\Proyectos\GamesDB\dashboard
pip install -r requirements.txt
```

## Correr el dashboard

```bash
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

Luego abrir en el navegador: http://localhost:8000

Para acceder desde la Switch o desde la red Tailscale:
http://<IP-Tailscale-laptop>:8000

## Endpoints disponibles

| Endpoint             | Descripción                              |
|----------------------|------------------------------------------|
| GET /                | Dashboard (HTML)                         |
| GET /api/stats       | Stats generales (sp_reporte_diario)      |
| GET /api/top_juegos  | Top 10 juegos por jugadores actuales     |
| GET /api/mirroring   | Estado del mirroring SQL Server          |
| GET /api/linked_server | Estado del linked server MySQL         |
| GET /api/bitacora    | Últimos 20 cambios de la bitácora        |
| GET /api/generos     | Top 10 géneros con rating y precio       |

## Auto-refresh

El dashboard se actualiza automáticamente cada **30 segundos**.
El botón "↻ Actualizar" fuerza una actualización inmediata.

## Notas

- El mirroring muestra SYNCHRONIZED / SYNCHRONIZING / SUSPENDED según el estado real.
- Si el linked server MySQL (Switch) no responde, aparece OFFLINE en rojo — no rompe el dashboard.
- El Steam Loader se marca ACTIVO si la última estadística tiene menos de 10 minutos.
- Para cambiar el servidor SQL edita la línea `SERVER` en `main.py`.
