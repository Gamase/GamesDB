-- =============================================================
-- GamesDB -- Bitacora, Usuarios y Triggers de Auditoria
-- SQL Server 2017+  (STRING_AGG, FOR JSON PATH en triggers)
-- =============================================================


-- =============================================================
-- BASE DE DATOS Bitacora_Central
-- =============================================================

USE master;
GO

IF DB_ID(N'Bitacora_Central') IS NULL
    CREATE DATABASE Bitacora_Central
        COLLATE Modern_Spanish_CI_AI;
GO

USE Bitacora_Central;
GO

IF OBJECT_ID('dbo.bitacora', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.bitacora (
        id_bitacora      BIGINT          NOT NULL IDENTITY(1,1),
        base_datos       SYSNAME         NOT NULL,
        tabla            SYSNAME         NOT NULL,
        operacion        CHAR(6)         NOT NULL,   -- INSERT | UPDATE | DELETE
        fecha            DATETIME2(3)    NOT NULL
            CONSTRAINT DF_bitacora_fecha DEFAULT SYSUTCDATETIME(),
        usuario          NVARCHAR(128)   NOT NULL,
        datos_antes      NVARCHAR(MAX)   NULL,       -- JSON de filas en deleted
        datos_despues    NVARCHAR(MAX)   NULL,       -- JSON de filas en inserted
        campos_cambiados NVARCHAR(MAX)   NULL,       -- JSON array solo para UPDATE

        CONSTRAINT PK_bitacora    PRIMARY KEY (id_bitacora),
        CONSTRAINT CK_bitacora_op CHECK (operacion IN ('INSERT', 'UPDATE', 'DELETE'))
    );

    -- Indices para consultas de auditoria frecuentes
    CREATE INDEX IX_bitacora_entidad_fecha
        ON dbo.bitacora (base_datos, tabla, fecha DESC);

    CREATE INDEX IX_bitacora_usuario_fecha
        ON dbo.bitacora (usuario, fecha DESC);
END;
GO


-- =============================================================
-- LOGINS DE SERVIDOR
-- =============================================================

USE master;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.server_principals
    WHERE name = N'usr_escritura' AND type = 'S'
)
    CREATE LOGIN usr_escritura
        WITH PASSWORD       = 'Writers2025!',
             DEFAULT_DATABASE = Bitacora_Central,
             CHECK_EXPIRATION = OFF,
             CHECK_POLICY     = ON;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.server_principals
    WHERE name = N'usr_lectura' AND type = 'S'
)
    CREATE LOGIN usr_lectura
        WITH PASSWORD       = 'Readers2025!',
             DEFAULT_DATABASE = Bitacora_Central,
             CHECK_EXPIRATION = OFF,
             CHECK_POLICY     = ON;
GO


-- =============================================================
-- USUARIOS Y PERMISOS en Bitacora_Central
-- =============================================================

USE Bitacora_Central;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.database_principals WHERE name = N'usr_escritura'
)
    CREATE USER usr_escritura FOR LOGIN usr_escritura;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.database_principals WHERE name = N'usr_lectura'
)
    CREATE USER usr_lectura FOR LOGIN usr_lectura;
GO

-- usr_escritura: solo INSERT en bitacora
GRANT INSERT ON dbo.bitacora TO usr_escritura;
DENY  SELECT ON dbo.bitacora TO usr_escritura;
DENY  UPDATE ON dbo.bitacora TO usr_escritura;
DENY  DELETE ON dbo.bitacora TO usr_escritura;

-- usr_lectura: solo SELECT en bitacora
GRANT SELECT ON dbo.bitacora TO usr_lectura;
DENY  INSERT ON dbo.bitacora TO usr_lectura;
DENY  UPDATE ON dbo.bitacora TO usr_lectura;
DENY  DELETE ON dbo.bitacora TO usr_lectura;
GO


-- =============================================================
-- CONFIGURACION CROSS-DATABASE EN GamesDB
--
-- TRUSTWORTHY permite que los triggers usen WITH EXECUTE AS con
-- un contexto que cruza bases de datos. Activarlo es seguro
-- cuando el propietario de GamesDB es el mismo sa / DBA que
-- administra Bitacora_Central.
-- =============================================================

USE master;
GO

ALTER DATABASE GamesDB SET TRUSTWORTHY ON;
GO

USE GamesDB;
GO

-- usr_escritura debe existir en GamesDB para poder usarse
-- en WITH EXECUTE AS dentro de los triggers
IF NOT EXISTS (
    SELECT 1 FROM sys.database_principals WHERE name = N'usr_escritura'
)
    CREATE USER usr_escritura FOR LOGIN usr_escritura;
GO


-- =============================================================
-- TRIGGER: trg_bitacora_juegos
-- =============================================================

IF OBJECT_ID('dbo.trg_bitacora_juegos', 'TR') IS NOT NULL
    DROP TRIGGER dbo.trg_bitacora_juegos;
GO

CREATE TRIGGER dbo.trg_bitacora_juegos
ON dbo.juegos
WITH EXECUTE AS 'usr_escritura'     -- escribe en Bitacora_Central como usr_escritura
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- Detectar tipo de operacion segun presencia de filas en inserted / deleted
    DECLARE @operacion CHAR(6) =
        CASE
            WHEN (SELECT COUNT(*) FROM inserted) > 0
             AND (SELECT COUNT(*) FROM deleted)  = 0 THEN 'INSERT'
            WHEN (SELECT COUNT(*) FROM inserted) = 0
             AND (SELECT COUNT(*) FROM deleted)  > 0 THEN 'DELETE'
            ELSE 'UPDATE'
        END;

    -- Serializar filas afectadas a JSON
    DECLARE @datos_antes    NVARCHAR(MAX) = NULL;
    DECLARE @datos_despues  NVARCHAR(MAX) = NULL;
    DECLARE @campos_cambiados NVARCHAR(MAX) = NULL;

    IF @operacion IN ('UPDATE', 'DELETE')
        SET @datos_antes = (
            SELECT
                id_juego, steam_appid, nombre, descripcion, precio,
                fecha_lanzamiento, desarrollador, publicador,
                fecha_creacion, fecha_actualizacion
            FROM deleted
            FOR JSON PATH
        );

    IF @operacion IN ('INSERT', 'UPDATE')
        SET @datos_despues = (
            SELECT
                id_juego, steam_appid, nombre, descripcion, precio,
                fecha_lanzamiento, desarrollador, publicador,
                fecha_creacion, fecha_actualizacion
            FROM inserted
            FOR JSON PATH
        );

    -- Detectar exactamente que columnas cambiaron de valor (solo en UPDATE)
    -- Cada SELECT sin FROM produce 1 fila si EXISTS es verdadero, 0 si es falso.
    -- El resultado es un JSON array: ["nombre","precio"]
    IF @operacion = 'UPDATE'
    BEGIN
        SELECT @campos_cambiados =
            '[' + STRING_AGG('"' + campo + '"', ',') + ']'
        FROM (
            SELECT 'nombre' AS campo
            WHERE EXISTS (
                SELECT 1 FROM inserted i
                JOIN deleted d ON d.id_juego = i.id_juego
                WHERE ISNULL(i.nombre, '') <> ISNULL(d.nombre, '')
            )
            UNION ALL
            SELECT 'descripcion'
            WHERE EXISTS (
                SELECT 1 FROM inserted i
                JOIN deleted d ON d.id_juego = i.id_juego
                WHERE ISNULL(i.descripcion, '') <> ISNULL(d.descripcion, '')
            )
            UNION ALL
            SELECT 'precio'
            WHERE EXISTS (
                SELECT 1 FROM inserted i
                JOIN deleted d ON d.id_juego = i.id_juego
                WHERE i.precio <> d.precio
            )
            UNION ALL
            SELECT 'fecha_lanzamiento'
            WHERE EXISTS (
                SELECT 1 FROM inserted i
                JOIN deleted d ON d.id_juego = i.id_juego
                WHERE ISNULL(CAST(i.fecha_lanzamiento AS NVARCHAR(20)), '')
                   <> ISNULL(CAST(d.fecha_lanzamiento AS NVARCHAR(20)), '')
            )
            UNION ALL
            SELECT 'desarrollador'
            WHERE EXISTS (
                SELECT 1 FROM inserted i
                JOIN deleted d ON d.id_juego = i.id_juego
                WHERE ISNULL(i.desarrollador, '') <> ISNULL(d.desarrollador, '')
            )
            UNION ALL
            SELECT 'publicador'
            WHERE EXISTS (
                SELECT 1 FROM inserted i
                JOIN deleted d ON d.id_juego = i.id_juego
                WHERE ISNULL(i.publicador, '') <> ISNULL(d.publicador, '')
            )
        ) AS cambios;
    END;

    INSERT INTO Bitacora_Central.dbo.bitacora
        (base_datos, tabla, operacion, usuario,
         datos_antes, datos_despues, campos_cambiados)
    VALUES
        (DB_NAME(), N'juegos', @operacion,
         ISNULL(ORIGINAL_LOGIN(), SYSTEM_USER),   -- ORIGINAL_LOGIN preserva al caller real
         @datos_antes, @datos_despues, @campos_cambiados);

    SET NOCOUNT OFF;
END;
GO


-- =============================================================
-- TRIGGER: trg_bitacora_estadisticas
-- =============================================================

IF OBJECT_ID('dbo.trg_bitacora_estadisticas', 'TR') IS NOT NULL
    DROP TRIGGER dbo.trg_bitacora_estadisticas;
GO

CREATE TRIGGER dbo.trg_bitacora_estadisticas
ON dbo.estadisticas
WITH EXECUTE AS 'usr_escritura'
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @operacion CHAR(6) =
        CASE
            WHEN (SELECT COUNT(*) FROM inserted) > 0
             AND (SELECT COUNT(*) FROM deleted)  = 0 THEN 'INSERT'
            WHEN (SELECT COUNT(*) FROM inserted) = 0
             AND (SELECT COUNT(*) FROM deleted)  > 0 THEN 'DELETE'
            ELSE 'UPDATE'
        END;

    DECLARE @datos_antes      NVARCHAR(MAX) = NULL;
    DECLARE @datos_despues    NVARCHAR(MAX) = NULL;
    DECLARE @campos_cambiados NVARCHAR(MAX) = NULL;

    IF @operacion IN ('UPDATE', 'DELETE')
        SET @datos_antes = (
            SELECT
                id_estadistica, id_juego,
                jugadores_actuales, jugadores_pico,
                total_resenas, fecha_registro
            FROM deleted
            FOR JSON PATH
        );

    IF @operacion IN ('INSERT', 'UPDATE')
        SET @datos_despues = (
            SELECT
                id_estadistica, id_juego,
                jugadores_actuales, jugadores_pico,
                total_resenas, fecha_registro
            FROM inserted
            FOR JSON PATH
        );

    IF @operacion = 'UPDATE'
    BEGIN
        SELECT @campos_cambiados =
            '[' + STRING_AGG('"' + campo + '"', ',') + ']'
        FROM (
            SELECT 'jugadores_actuales' AS campo
            WHERE EXISTS (
                SELECT 1 FROM inserted i
                JOIN deleted d ON d.id_estadistica = i.id_estadistica
                WHERE i.jugadores_actuales <> d.jugadores_actuales
            )
            UNION ALL
            SELECT 'jugadores_pico'
            WHERE EXISTS (
                SELECT 1 FROM inserted i
                JOIN deleted d ON d.id_estadistica = i.id_estadistica
                WHERE i.jugadores_pico <> d.jugadores_pico
            )
            UNION ALL
            SELECT 'total_resenas'
            WHERE EXISTS (
                SELECT 1 FROM inserted i
                JOIN deleted d ON d.id_estadistica = i.id_estadistica
                WHERE i.total_resenas <> d.total_resenas
            )
        ) AS cambios;
    END;

    INSERT INTO Bitacora_Central.dbo.bitacora
        (base_datos, tabla, operacion, usuario,
         datos_antes, datos_despues, campos_cambiados)
    VALUES
        (DB_NAME(), N'estadisticas', @operacion,
         ISNULL(ORIGINAL_LOGIN(), SYSTEM_USER),
         @datos_antes, @datos_despues, @campos_cambiados);

    SET NOCOUNT OFF;
END;
GO


-- =============================================================
-- Verificacion de objetos creados
-- =============================================================

-- Triggers en GamesDB
SELECT
    t.name                                              AS trigger_nombre,
    OBJECT_NAME(t.parent_id)                            AS tabla,
    STRING_AGG(te.type_desc, ' | ')
        WITHIN GROUP (ORDER BY te.type_desc)            AS eventos,
    t.is_disabled,
    t.is_instead_of_trigger,
    t.create_date
FROM sys.triggers       t
JOIN sys.trigger_events te ON te.object_id = t.object_id
WHERE t.name IN (
    N'trg_bitacora_juegos',
    N'trg_bitacora_estadisticas'
)
GROUP BY t.object_id, t.name, t.parent_id,
         t.is_disabled, t.is_instead_of_trigger, t.create_date
ORDER BY t.name;
GO

-- Usuarios y permisos en Bitacora_Central
USE Bitacora_Central;
GO

SELECT
    dp.permission_name                                  AS permiso,
    dp.state_desc                                       AS estado,
    USER_NAME(dp.grantee_principal_id)                  AS usuario,
    OBJECT_SCHEMA_NAME(dp.major_id) + '.'
        + OBJECT_NAME(dp.major_id)                      AS objeto
FROM sys.database_permissions dp
WHERE OBJECT_NAME(dp.major_id) = N'bitacora'
  AND dp.class = 1
ORDER BY usuario, permiso;
GO
