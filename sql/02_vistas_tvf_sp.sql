-- =============================================================
-- GamesDB -- Vistas, TVFs y Stored Procedures
-- SQL Server 2017+  (vw_top_juegos usa STRING_AGG)
-- =============================================================

USE GamesDB;
GO

-- =============================================================
-- V I S T A S
-- =============================================================

-- -------------------------------------------------------------
-- vw_top_juegos
-- Juegos con mayor pico historico de jugadores, generos
-- concatenados y datos de resenas.
-- Orden recomendado al consultar: ORDER BY jugadores_pico_maximo DESC
-- -------------------------------------------------------------
IF OBJECT_ID('dbo.vw_top_juegos', 'V') IS NOT NULL
    DROP VIEW dbo.vw_top_juegos;
GO

CREATE VIEW dbo.vw_top_juegos
AS
SELECT
    j.id_juego,
    j.steam_appid,
    j.nombre,
    j.desarrollador,
    j.publicador,
    j.precio,
    j.fecha_lanzamiento,
    e.jugadores_pico_maximo,
    e.ultima_lectura,
    STRING_AGG(g.nombre, ', ')
        WITHIN GROUP (ORDER BY g.nombre)    AS generos,
    r.porcentaje_positivo,
    r.descripcion_general
FROM dbo.juegos j
LEFT JOIN (
    SELECT
        id_juego,
        MAX(jugadores_pico)     AS jugadores_pico_maximo,
        MAX(fecha_registro)     AS ultima_lectura
    FROM dbo.estadisticas
    GROUP BY id_juego
)                        e  ON  e.id_juego  = j.id_juego
LEFT JOIN dbo.juegos_generos jg ON jg.id_juego  = j.id_juego
LEFT JOIN dbo.generos         g  ON  g.id_genero = jg.id_genero
LEFT JOIN dbo.resenas         r  ON  r.id_juego  = j.id_juego
GROUP BY
    j.id_juego, j.steam_appid, j.nombre, j.desarrollador, j.publicador,
    j.precio, j.fecha_lanzamiento,
    e.jugadores_pico_maximo, e.ultima_lectura,
    r.porcentaje_positivo, r.descripcion_general;
GO


-- -------------------------------------------------------------
-- vw_juegos_por_genero
-- Cantidad de juegos, precio promedio y rating promedio por genero.
-- Orden recomendado: ORDER BY cantidad_juegos DESC
-- -------------------------------------------------------------
IF OBJECT_ID('dbo.vw_juegos_por_genero', 'V') IS NOT NULL
    DROP VIEW dbo.vw_juegos_por_genero;
GO

CREATE VIEW dbo.vw_juegos_por_genero
AS
SELECT
    g.id_genero,
    g.nombre                                        AS genero,
    COUNT(jg.id_juego)                              AS cantidad_juegos,
    CAST(AVG(j.precio)                  AS DECIMAL(10,2))   AS precio_promedio,
    CAST(AVG(r.porcentaje_positivo)     AS DECIMAL(5,2))    AS rating_promedio,
    CAST(MAX(r.porcentaje_positivo)     AS DECIMAL(5,2))    AS mejor_rating
FROM dbo.generos              g
LEFT JOIN dbo.juegos_generos jg ON jg.id_genero = g.id_genero
LEFT JOIN dbo.juegos          j  ON  j.id_juego  = jg.id_juego
LEFT JOIN dbo.resenas         r  ON  r.id_juego  = j.id_juego
GROUP BY g.id_genero, g.nombre;
GO


-- -------------------------------------------------------------
-- vw_mejores_resenas
-- Juegos con porcentaje_positivo mayor a 90%.
-- -------------------------------------------------------------
IF OBJECT_ID('dbo.vw_mejores_resenas', 'V') IS NOT NULL
    DROP VIEW dbo.vw_mejores_resenas;
GO

CREATE VIEW dbo.vw_mejores_resenas
AS
SELECT
    j.id_juego,
    j.nombre,
    j.desarrollador,
    j.precio,
    j.fecha_lanzamiento,
    r.positivas,
    r.negativas,
    r.positivas + r.negativas       AS total_resenas,
    r.porcentaje_positivo,
    r.descripcion_general
FROM dbo.juegos  j
JOIN dbo.resenas r ON r.id_juego = j.id_juego
WHERE r.porcentaje_positivo > 90;
GO


-- =============================================================
-- T V F s  (Inline Table-Valued Functions)
-- =============================================================

-- -------------------------------------------------------------
-- tvf_juegos_por_precio
-- Juegos cuyo precio esta entre @precio_min y @precio_max.
-- Uso: SELECT * FROM tvf_juegos_por_precio(0, 9.99) ORDER BY precio
-- -------------------------------------------------------------
IF OBJECT_ID('dbo.tvf_juegos_por_precio', 'IF') IS NOT NULL
    DROP FUNCTION dbo.tvf_juegos_por_precio;
GO

CREATE FUNCTION dbo.tvf_juegos_por_precio
(
    @precio_min DECIMAL(10,2),
    @precio_max DECIMAL(10,2)
)
RETURNS TABLE
AS
RETURN
(
    SELECT
        j.id_juego,
        j.steam_appid,
        j.nombre,
        j.precio,
        j.desarrollador,
        j.publicador,
        j.fecha_lanzamiento,
        r.porcentaje_positivo,
        r.descripcion_general
    FROM dbo.juegos  j
    LEFT JOIN dbo.resenas r ON r.id_juego = j.id_juego
    WHERE j.precio BETWEEN @precio_min AND @precio_max
);
GO


-- -------------------------------------------------------------
-- tvf_juegos_por_rating
-- Juegos con porcentaje_positivo >= @porcentaje_min.
-- Uso: SELECT * FROM tvf_juegos_por_rating(85) ORDER BY porcentaje_positivo DESC
-- -------------------------------------------------------------
IF OBJECT_ID('dbo.tvf_juegos_por_rating', 'IF') IS NOT NULL
    DROP FUNCTION dbo.tvf_juegos_por_rating;
GO

CREATE FUNCTION dbo.tvf_juegos_por_rating
(
    @porcentaje_min DECIMAL(5,2)
)
RETURNS TABLE
AS
RETURN
(
    SELECT
        j.id_juego,
        j.steam_appid,
        j.nombre,
        j.precio,
        j.desarrollador,
        r.positivas,
        r.negativas,
        r.positivas + r.negativas       AS total_resenas,
        r.porcentaje_positivo,
        r.descripcion_general
    FROM dbo.juegos  j
    JOIN dbo.resenas r ON r.id_juego = j.id_juego
    WHERE r.porcentaje_positivo >= @porcentaje_min
);
GO


-- -------------------------------------------------------------
-- tvf_estadisticas_por_juego
-- Historial de estadisticas de un juego con deltas entre
-- snapshots consecutivos.
-- Uso: SELECT * FROM tvf_estadisticas_por_juego(1) ORDER BY fecha_registro
-- -------------------------------------------------------------
IF OBJECT_ID('dbo.tvf_estadisticas_por_juego', 'IF') IS NOT NULL
    DROP FUNCTION dbo.tvf_estadisticas_por_juego;
GO

CREATE FUNCTION dbo.tvf_estadisticas_por_juego
(
    @id_juego INT
)
RETURNS TABLE
AS
RETURN
(
    SELECT
        e.id_estadistica,
        e.fecha_registro,
        e.jugadores_actuales,
        e.jugadores_pico,
        e.total_resenas,
        e.jugadores_actuales
            - LAG(e.jugadores_actuales, 1, e.jugadores_actuales)
              OVER (ORDER BY e.fecha_registro)      AS delta_jugadores,
        e.jugadores_pico
            - LAG(e.jugadores_pico, 1, e.jugadores_pico)
              OVER (ORDER BY e.fecha_registro)      AS delta_pico,
        e.total_resenas
            - LAG(e.total_resenas, 1, e.total_resenas)
              OVER (ORDER BY e.fecha_registro)      AS delta_resenas
    FROM dbo.estadisticas e
    WHERE e.id_juego = @id_juego
);
GO


-- =============================================================
-- S T O R E D   P R O C E D U R E S
-- =============================================================

-- -------------------------------------------------------------
-- sp_reporte_diario
-- Devuelve 4 result sets:
--   1. Resumen general de la carga
--   2. Top 5 por jugadores actuales (ultimo snapshot por juego)
--   3. Top 10 generos por cantidad de juegos
--   4. Top 5 juegos con mayor variacion de jugadores entre
--      los dos ultimos snapshots
--
-- @fecha DATE = NULL  -> usa la fecha UTC actual
-- -------------------------------------------------------------
IF OBJECT_ID('dbo.sp_reporte_diario', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_reporte_diario;
GO

CREATE PROCEDURE dbo.sp_reporte_diario
    @fecha DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @fecha IS NULL
        SET @fecha = CAST(SYSUTCDATETIME() AS DATE);

    -- Materializar ultimo snapshot por juego (evita multiple evaluacion del CTE)
    SELECT
        e.id_estadistica,
        e.id_juego,
        e.jugadores_actuales,
        e.jugadores_pico,
        e.total_resenas,
        e.fecha_registro,
        ROW_NUMBER() OVER (PARTITION BY e.id_juego ORDER BY e.fecha_registro DESC) AS rn
    INTO #ultima_stat
    FROM dbo.estadisticas e;

    CREATE INDEX ix_tmp ON #ultima_stat (rn, id_juego);

    -- -------------------------------------------------------
    -- RS 1: Resumen general
    -- -------------------------------------------------------
    SELECT
        @fecha                                              AS fecha_reporte,
        COUNT(DISTINCT j.id_juego)                          AS total_juegos,
        COUNT(DISTINCT r.id_resena)                         AS juegos_con_resenas,
        SUM(u.jugadores_actuales)                           AS jugadores_actuales_total,
        CAST(AVG(CAST(u.jugadores_actuales AS FLOAT))
             AS DECIMAL(12,0))                              AS promedio_jugadores,
        MAX(u.jugadores_pico)                               AS pico_maximo_registrado,
        CAST(AVG(r.porcentaje_positivo) AS DECIMAL(5,2))    AS rating_promedio_global,
        MAX(u.fecha_registro)                               AS ultima_actualizacion,
        COUNT(CASE WHEN CAST(j.fecha_creacion AS DATE) = @fecha THEN 1 END)
                                                            AS juegos_nuevos_hoy
    FROM dbo.juegos           j
    LEFT JOIN #ultima_stat   u ON u.id_juego = j.id_juego AND u.rn = 1
    LEFT JOIN dbo.resenas    r ON r.id_juego  = j.id_juego;

    -- -------------------------------------------------------
    -- RS 2: Top 5 por jugadores actuales (ultimo snapshot)
    -- -------------------------------------------------------
    SELECT TOP 5
        j.nombre,
        j.desarrollador,
        u.jugadores_actuales,
        u.jugadores_pico,
        j.precio,
        r.porcentaje_positivo,
        r.descripcion_general,
        u.fecha_registro                AS ultima_lectura
    FROM #ultima_stat  u
    JOIN dbo.juegos    j ON j.id_juego = u.id_juego
    LEFT JOIN dbo.resenas r ON r.id_juego = j.id_juego
    WHERE u.rn = 1
    ORDER BY u.jugadores_actuales DESC;

    -- -------------------------------------------------------
    -- RS 3: Top 10 generos por cantidad de juegos
    -- -------------------------------------------------------
    SELECT TOP 10
        g.nombre                                            AS genero,
        COUNT(DISTINCT jg.id_juego)                         AS cantidad_juegos,
        CAST(AVG(r.porcentaje_positivo) AS DECIMAL(5,2))    AS rating_promedio,
        CAST(AVG(j.precio)              AS DECIMAL(10,2))   AS precio_promedio
    FROM dbo.generos              g
    JOIN dbo.juegos_generos      jg ON jg.id_genero = g.id_genero
    JOIN dbo.juegos               j  ON  j.id_juego  = jg.id_juego
    LEFT JOIN dbo.resenas        r  ON  r.id_juego   = j.id_juego
    GROUP BY g.id_genero, g.nombre
    ORDER BY cantidad_juegos DESC;

    -- -------------------------------------------------------
    -- RS 4: Top 5 mayor variacion entre los dos ultimos snapshots
    -- -------------------------------------------------------
    SELECT TOP 5
        j.nombre,
        ahora.jugadores_actuales                            AS jugadores_ahora,
        prev.jugadores_actuales                             AS jugadores_anterior,
        ahora.jugadores_actuales - prev.jugadores_actuales  AS variacion_absoluta,
        CAST(
            (CAST(ahora.jugadores_actuales - prev.jugadores_actuales AS FLOAT)
             / NULLIF(prev.jugadores_actuales, 0)) * 100
        AS DECIMAL(8,1))                                    AS variacion_pct,
        ahora.fecha_registro                                AS snapshot_actual,
        prev.fecha_registro                                 AS snapshot_anterior
    FROM #ultima_stat ahora
    JOIN #ultima_stat prev  ON  prev.id_juego = ahora.id_juego AND prev.rn = 2
    JOIN dbo.juegos   j     ON  j.id_juego    = ahora.id_juego
    WHERE ahora.rn = 1
    ORDER BY ABS(ahora.jugadores_actuales - prev.jugadores_actuales) DESC;

    DROP TABLE #ultima_stat;
END;
GO


-- -------------------------------------------------------------
-- sp_sincronizar_mysql
-- Sincroniza juegos y estadisticas hacia MySQL via Linked Server.
--
-- PREREQUISITO: configurar el linked server antes de ejecutar:
--
--   EXEC sp_addlinkedserver
--       @server     = 'MYSQL_GAMESDB',
--       @srvproduct = 'MySQL',
--       @provider   = 'MSDASQL',
--       @datasrc    = 'DSN_MySQL_GamesDB';   -- nombre del DSN ODBC
--
--   EXEC sp_addlinkedsrvlogin
--       @rmtsrvname  = 'MYSQL_GAMESDB',
--       @useself     = 'FALSE',
--       @rmtuser     = 'usuario_mysql',
--       @rmtpassword = 'password_mysql';
--
-- La tabla MySQL debe tener steam_appid como UNIQUE KEY y
-- id_estadistica como campo compatible con INT de SQL Server.
--
-- @linked_server  SYSNAME       Nombre del linked server
-- @modo           NVARCHAR(20)  FULL     = truncate + reinsertar todo
--                               INCREMENTAL = solo nuevos / cambiados
-- -------------------------------------------------------------
IF OBJECT_ID('dbo.sp_sincronizar_mysql', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_sincronizar_mysql;
GO

CREATE PROCEDURE dbo.sp_sincronizar_mysql
    @linked_server  SYSNAME       = N'MYSQL_GAMESDB',
    @modo           NVARCHAR(20)  = N'INCREMENTAL'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @sql            NVARCHAR(MAX);
    DECLARE @inicio         DATETIME2   = SYSUTCDATETIME();
    DECLARE @j_insertados   INT         = 0;
    DECLARE @j_actualizados INT         = 0;
    DECLARE @e_insertados   INT         = 0;
    DECLARE @max_stat_mysql INT         = 0;

    -- Validaciones previas
    IF @modo NOT IN (N'FULL', N'INCREMENTAL')
    BEGIN
        RAISERROR('@modo invalido. Use FULL o INCREMENTAL.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS (
        SELECT 1 FROM sys.servers
        WHERE name = @linked_server AND is_linked = 1
    )
    BEGIN
        DECLARE @err_ls NVARCHAR(500) =
            'Linked server [' + @linked_server
            + '] no encontrado. Configuralo con sp_addlinkedserver antes de ejecutar este SP.';
        RAISERROR(@err_ls, 16, 1);
        RETURN;
    END;

    BEGIN TRY

        -- =======================================================
        -- MODO FULL: limpiar MySQL y reinsertar todo
        -- =======================================================
        IF @modo = N'FULL'
        BEGIN
            -- Deshabilitar FK en MySQL y limpiar en orden inverso
            SET @sql = N'EXEC(''SET FOREIGN_KEY_CHECKS = 0'') AT [' + @linked_server + N']';
            EXEC sp_executesql @sql;

            SET @sql = N'EXEC(''TRUNCATE TABLE gamesdb.estadisticas'') AT [' + @linked_server + N']';
            EXEC sp_executesql @sql;

            SET @sql = N'EXEC(''TRUNCATE TABLE gamesdb.resenas'') AT [' + @linked_server + N']';
            EXEC sp_executesql @sql;

            SET @sql = N'EXEC(''TRUNCATE TABLE gamesdb.juegos_generos'') AT [' + @linked_server + N']';
            EXEC sp_executesql @sql;

            SET @sql = N'EXEC(''TRUNCATE TABLE gamesdb.juegos'') AT [' + @linked_server + N']';
            EXEC sp_executesql @sql;

            SET @sql = N'EXEC(''TRUNCATE TABLE gamesdb.generos'') AT [' + @linked_server + N']';
            EXEC sp_executesql @sql;

            SET @sql = N'EXEC(''SET FOREIGN_KEY_CHECKS = 1'') AT [' + @linked_server + N']';
            EXEC sp_executesql @sql;

            -- Insertar generos
            SET @sql = N'
                INSERT INTO OPENQUERY([' + @linked_server + N'],
                    ''SELECT id_genero, nombre FROM gamesdb.generos WHERE 1=0'')
                SELECT id_genero, nombre
                FROM GamesDB.dbo.generos';
            EXEC sp_executesql @sql;

            -- Insertar juegos
            SET @sql = N'
                INSERT INTO OPENQUERY([' + @linked_server + N'],
                    ''SELECT steam_appid, nombre, descripcion, precio,
                             fecha_lanzamiento, desarrollador, publicador
                      FROM gamesdb.juegos WHERE 1=0'')
                SELECT
                    j.steam_appid,
                    j.nombre,
                    CAST(j.descripcion AS NVARCHAR(MAX)),
                    j.precio,
                    j.fecha_lanzamiento,
                    j.desarrollador,
                    j.publicador
                FROM GamesDB.dbo.juegos j';
            EXEC sp_executesql @sql;
            SET @j_insertados = @@ROWCOUNT;

            -- Insertar juegos_generos
            SET @sql = N'
                INSERT INTO OPENQUERY([' + @linked_server + N'],
                    ''SELECT id_juego, id_genero FROM gamesdb.juegos_generos WHERE 1=0'')
                SELECT jg.id_juego, jg.id_genero
                FROM GamesDB.dbo.juegos_generos jg';
            EXEC sp_executesql @sql;

            -- Insertar estadisticas (todas)
            SET @sql = N'
                INSERT INTO OPENQUERY([' + @linked_server + N'],
                    ''SELECT id_estadistica, id_juego, jugadores_actuales,
                             jugadores_pico, total_resenas, fecha_registro
                      FROM gamesdb.estadisticas WHERE 1=0'')
                SELECT
                    e.id_estadistica,
                    e.id_juego,
                    e.jugadores_actuales,
                    e.jugadores_pico,
                    e.total_resenas,
                    e.fecha_registro
                FROM GamesDB.dbo.estadisticas e';
            EXEC sp_executesql @sql;
            SET @e_insertados = @@ROWCOUNT;

            -- Insertar resenas
            SET @sql = N'
                INSERT INTO OPENQUERY([' + @linked_server + N'],
                    ''SELECT id_juego, positivas, negativas,
                             porcentaje_positivo, descripcion_general
                      FROM gamesdb.resenas WHERE 1=0'')
                SELECT
                    r.id_juego,
                    r.positivas,
                    r.negativas,
                    r.porcentaje_positivo,
                    r.descripcion_general
                FROM GamesDB.dbo.resenas r';
            EXEC sp_executesql @sql;
        END; -- FULL


        -- =======================================================
        -- MODO INCREMENTAL
        -- =======================================================
        IF @modo = N'INCREMENTAL'
        BEGIN
            -- Obtener appids ya existentes en MySQL
            SET @sql = N'
                SELECT steam_appid
                INTO #mysql_appids
                FROM OPENQUERY([' + @linked_server + N'],
                    ''SELECT steam_appid FROM gamesdb.juegos'')';
            EXEC sp_executesql @sql;

            -- Juegos nuevos (no existen en MySQL)
            SET @sql = N'
                INSERT INTO OPENQUERY([' + @linked_server + N'],
                    ''SELECT steam_appid, nombre, descripcion, precio,
                             fecha_lanzamiento, desarrollador, publicador
                      FROM gamesdb.juegos WHERE 1=0'')
                SELECT
                    j.steam_appid,
                    j.nombre,
                    CAST(j.descripcion AS NVARCHAR(MAX)),
                    j.precio,
                    j.fecha_lanzamiento,
                    j.desarrollador,
                    j.publicador
                FROM GamesDB.dbo.juegos j
                WHERE j.steam_appid NOT IN (SELECT steam_appid FROM #mysql_appids)';
            EXEC sp_executesql @sql;
            SET @j_insertados = @@ROWCOUNT;

            -- Juegos modificados en las ultimas 24 h: borrar en MySQL y reinsertar
            -- (evita reconstruir UPDATE dinamico campo a campo)
            IF EXISTS (
                SELECT 1 FROM dbo.juegos
                WHERE fecha_actualizacion >= DATEADD(HOUR, -24, SYSUTCDATETIME())
                  AND steam_appid IN (SELECT steam_appid FROM #mysql_appids)
            )
            BEGIN
                -- Construir lista de appids modificados para el DELETE remoto
                DECLARE @appids_csv NVARCHAR(MAX) = N'';
                SELECT @appids_csv = @appids_csv
                    + CAST(j.steam_appid AS NVARCHAR(12)) + N','
                FROM dbo.juegos j
                WHERE j.fecha_actualizacion >= DATEADD(HOUR, -24, SYSUTCDATETIME())
                  AND j.steam_appid IN (SELECT steam_appid FROM #mysql_appids);

                SET @appids_csv = LEFT(@appids_csv, LEN(@appids_csv) - 1); -- quitar coma final

                -- Borrar en MySQL los registros a actualizar
                SET @sql = N'EXEC(''DELETE FROM gamesdb.juegos WHERE steam_appid IN ('
                           + @appids_csv + N')'') AT [' + @linked_server + N']';
                EXEC sp_executesql @sql;

                -- Reinsertar actualizados
                SET @sql = N'
                    INSERT INTO OPENQUERY([' + @linked_server + N'],
                        ''SELECT steam_appid, nombre, descripcion, precio,
                                 fecha_lanzamiento, desarrollador, publicador
                          FROM gamesdb.juegos WHERE 1=0'')
                    SELECT
                        j.steam_appid,
                        j.nombre,
                        CAST(j.descripcion AS NVARCHAR(MAX)),
                        j.precio,
                        j.fecha_lanzamiento,
                        j.desarrollador,
                        j.publicador
                    FROM GamesDB.dbo.juegos j
                    WHERE j.fecha_actualizacion >= DATEADD(HOUR, -24, SYSUTCDATETIME())
                      AND j.steam_appid IN (' + @appids_csv + N')';
                EXEC sp_executesql @sql;
                SET @j_actualizados = @@ROWCOUNT;
            END;

            -- Estadisticas: solo registros con id > max que ya tiene MySQL
            SET @sql = N'
                SELECT ISNULL(MAX(id_estadistica), 0) AS max_id
                INTO #mysql_max_stat
                FROM OPENQUERY([' + @linked_server + N'],
                    ''SELECT COALESCE(MAX(id_estadistica), 0) AS id_estadistica
                      FROM gamesdb.estadisticas'')';
            EXEC sp_executesql @sql;

            SELECT @max_stat_mysql = max_id FROM #mysql_max_stat;
            DROP TABLE #mysql_max_stat;

            SET @sql = N'
                INSERT INTO OPENQUERY([' + @linked_server + N'],
                    ''SELECT id_estadistica, id_juego, jugadores_actuales,
                             jugadores_pico, total_resenas, fecha_registro
                      FROM gamesdb.estadisticas WHERE 1=0'')
                SELECT
                    e.id_estadistica,
                    e.id_juego,
                    e.jugadores_actuales,
                    e.jugadores_pico,
                    e.total_resenas,
                    e.fecha_registro
                FROM GamesDB.dbo.estadisticas e
                WHERE e.id_estadistica > ' + CAST(@max_stat_mysql AS NVARCHAR(12));
            EXEC sp_executesql @sql;
            SET @e_insertados = @@ROWCOUNT;

            IF OBJECT_ID('tempdb..#mysql_appids') IS NOT NULL
                DROP TABLE #mysql_appids;
        END; -- INCREMENTAL


        -- Resultado de la sincronizacion
        SELECT
            @linked_server                                              AS linked_server,
            @modo                                                       AS modo,
            @j_insertados                                               AS juegos_insertados,
            @j_actualizados                                             AS juegos_actualizados,
            @e_insertados                                               AS estadisticas_insertadas,
            DATEDIFF(MILLISECOND, @inicio, SYSUTCDATETIME())            AS duracion_ms,
            SYSUTCDATETIME()                                            AS timestamp_fin;

    END TRY
    BEGIN CATCH
        -- Limpieza de temporales si quedaron abiertos
        IF OBJECT_ID('tempdb..#mysql_appids')  IS NOT NULL DROP TABLE #mysql_appids;
        IF OBJECT_ID('tempdb..#mysql_max_stat') IS NOT NULL DROP TABLE #mysql_max_stat;

        DECLARE @err_msg  NVARCHAR(2048) = ERROR_MESSAGE();
        DECLARE @err_line INT            = ERROR_LINE();
        DECLARE @err_proc SYSNAME        = ISNULL(ERROR_PROCEDURE(), 'sp_sincronizar_mysql');

        RAISERROR(
            '[%s] linea %d: %s',
            16, 1,
            @err_proc, @err_line, @err_msg
        );
    END CATCH;
END;
GO


-- =============================================================
-- Verificacion de objetos creados
-- =============================================================
SELECT
    o.type_desc         AS tipo,
    SCHEMA_NAME(o.schema_id) + '.' + o.name    AS objeto,
    o.create_date
FROM sys.objects o
WHERE o.type IN ('V', 'IF', 'P')          -- vistas, TVFs inline, SPs
  AND o.schema_id = SCHEMA_ID('dbo')
  AND o.name IN (
      'vw_top_juegos', 'vw_juegos_por_genero', 'vw_mejores_resenas',
      'tvf_juegos_por_precio', 'tvf_juegos_por_rating', 'tvf_estadisticas_por_juego',
      'sp_reporte_diario', 'sp_sincronizar_mysql'
  )
ORDER BY o.type_desc, o.name;
GO
