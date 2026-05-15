#!/usr/bin/env python3
"""
steam_scheduler.py
Ejecuta steam_loader.main() cada 30 minutos en loop continuo.

Uso:
    python steam_scheduler.py
    Ctrl+C para detener limpiamente.
"""

import sys
import time
import logging
from datetime import datetime
from pathlib import Path

# Asegura que steam_loader.py sea encontrable desde cualquier directorio
_DIR = Path(__file__).parent
sys.path.insert(0, str(_DIR))

import steam_loader   # basicConfig de steam_loader corre aqui (nivel modulo)

# ---------------------------------------------------------------------------
# Configuracion
# ---------------------------------------------------------------------------
INTERVAL_OK    =  5 * 60   # segundos entre ejecuciones exitosas
INTERVAL_ERROR =  5 * 60   # segundos de espera tras fallo
NOTIFY_EVERY   =  5 * 60   # cada cuantos segundos mostrar tiempo restante


# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
def _setup_logging() -> logging.Logger:
    """
    Reemplaza los handlers que steam_loader instalo al importarse por los del
    scheduler (consola + steam_scheduler.log). Ambos modulos comparten el
    root logger, por lo que toda la salida queda en el mismo archivo.
    """
    fmt = logging.Formatter(
        '%(asctime)s  %(levelname)-8s  %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S',
    )

    root = logging.getLogger()
    root.setLevel(logging.INFO)
    root.handlers.clear()               # descarta handlers de steam_loader

    sh = logging.StreamHandler(sys.stdout)
    sh.setFormatter(fmt)
    root.addHandler(sh)

    fh = logging.FileHandler(_DIR / 'steam_scheduler.log', encoding='utf-8')
    fh.setFormatter(fmt)
    root.addHandler(fh)

    return logging.getLogger('scheduler')


# ---------------------------------------------------------------------------
# Espera con cuenta regresiva
# ---------------------------------------------------------------------------
def _esperar(segundos: int, log: logging.Logger) -> None:
    """Duerme @segundos mostrando tiempo restante cada NOTIFY_EVERY segundos."""
    restante = segundos
    while restante > 0:
        tramo    = min(NOTIFY_EVERY, restante)
        time.sleep(tramo)
        restante -= tramo
        if restante > 0:
            log.info('  Proxima ejecucion en %d min...', restante // 60)


# ---------------------------------------------------------------------------
# Loop principal
# ---------------------------------------------------------------------------
def main() -> None:
    log = _setup_logging()
    log.info('=== steam_scheduler iniciado  |  intervalo=%d min  |  Ctrl+C para detener ===',
             INTERVAL_OK // 60)

    run = 0

    while True:
        run   += 1
        inicio = datetime.now()
        log.info('--- Ejecucion #%d  inicio: %s ---',
                 run, inicio.strftime('%Y-%m-%d %H:%M:%S'))

        try:
            steam_loader.main()

            duracion = (datetime.now() - inicio).total_seconds()
            log.info('Ejecucion #%d OK  |  duracion: %.1f s', run, duracion)
            log.info('Esperando %d min hasta la proxima ejecucion...', INTERVAL_OK // 60)
            _esperar(INTERVAL_OK, log)

        except KeyboardInterrupt:
            raise   # propaga al handler externo de __main__

        except SystemExit as exc:
            duracion = (datetime.now() - inicio).total_seconds()
            if exc.code == 0:
                # steam_loader.main() termino limpiamente
                log.info('Ejecucion #%d finalizo (exit 0) en %.1f s', run, duracion)
                _esperar(INTERVAL_OK, log)
            else:
                log.error('Ejecucion #%d FALLO (exit %s) en %.1f s',
                          run, exc.code, duracion)
                log.info('Reintentando en %d min...', INTERVAL_ERROR // 60)
                _esperar(INTERVAL_ERROR, log)

        except Exception as exc:
            duracion = (datetime.now() - inicio).total_seconds()
            log.error('Ejecucion #%d ERROR en %.1f s: %s', run, duracion, exc)
            log.info('Reintentando en %d min...', INTERVAL_ERROR // 60)
            _esperar(INTERVAL_ERROR, log)


# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------
if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        logging.getLogger('scheduler').info(
            '=== Detenido por el usuario (Ctrl+C)  ejecuciones completadas: ver log ==='
        )
        sys.exit(0)
