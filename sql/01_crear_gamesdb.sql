-- =============================================================
-- GamesDB - Script de creacion de base de datos
-- SQL Server 2016+
-- =============================================================

USE master;
GO

IF DB_ID('GamesDB') IS NOT NULL
BEGIN
    ALTER DATABASE GamesDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE GamesDB;
END
GO

CREATE DATABASE GamesDB
    COLLATE Modern_Spanish_CI_AI;
GO

USE GamesDB;
GO

-- =============================================================
-- TABLA: juegos
-- =============================================================
CREATE TABLE juegos (
    id_juego            INT             NOT NULL IDENTITY(1,1),
    steam_appid         INT             NOT NULL,
    nombre              NVARCHAR(255)   NOT NULL,
    descripcion         NVARCHAR(MAX)   NULL,
    precio              DECIMAL(10,2)   NOT NULL DEFAULT 0.00,
    fecha_lanzamiento   DATE            NULL,
    desarrollador       NVARCHAR(255)   NULL,
    publicador          NVARCHAR(255)   NULL,
    fecha_creacion      DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    fecha_actualizacion DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_juegos          PRIMARY KEY (id_juego),
    CONSTRAINT UQ_juegos_appid    UNIQUE      (steam_appid),
    CONSTRAINT CK_juegos_precio   CHECK       (precio >= 0),
    CONSTRAINT CK_juegos_nombre   CHECK       (LEN(LTRIM(nombre)) > 0)
);
GO

-- =============================================================
-- TABLA: generos
-- =============================================================
CREATE TABLE generos (
    id_genero   INT             NOT NULL IDENTITY(1,1),
    nombre      NVARCHAR(100)   NOT NULL,

    CONSTRAINT PK_generos        PRIMARY KEY (id_genero),
    CONSTRAINT UQ_generos_nombre UNIQUE      (nombre),
    CONSTRAINT CK_generos_nombre CHECK       (LEN(LTRIM(nombre)) > 0)
);
GO

-- =============================================================
-- TABLA: juegos_generos  (relacion N:M)
-- =============================================================
CREATE TABLE juegos_generos (
    id_juego    INT NOT NULL,
    id_genero   INT NOT NULL,

    CONSTRAINT PK_juegos_generos PRIMARY KEY (id_juego, id_genero),
    CONSTRAINT FK_jg_juego       FOREIGN KEY (id_juego)
        REFERENCES juegos (id_juego)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT FK_jg_genero      FOREIGN KEY (id_genero)
        REFERENCES generos (id_genero)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);
GO

-- =============================================================
-- TABLA: estadisticas
-- =============================================================
CREATE TABLE estadisticas (
    id_estadistica      INT         NOT NULL IDENTITY(1,1),
    id_juego            INT         NOT NULL,
    jugadores_actuales  INT         NOT NULL DEFAULT 0,
    jugadores_pico      INT         NOT NULL DEFAULT 0,
    total_resenas       INT         NOT NULL DEFAULT 0,
    fecha_registro      DATETIME2   NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_estadisticas              PRIMARY KEY (id_estadistica),
    CONSTRAINT FK_estadisticas_juego        FOREIGN KEY (id_juego)
        REFERENCES juegos (id_juego)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT CK_estadisticas_actuales     CHECK (jugadores_actuales >= 0),
    CONSTRAINT CK_estadisticas_pico         CHECK (jugadores_pico >= 0),
    CONSTRAINT CK_estadisticas_total        CHECK (total_resenas >= 0),
    CONSTRAINT CK_estadisticas_pico_actual  CHECK (jugadores_pico >= jugadores_actuales)
);
GO

-- =============================================================
-- TABLA: resenas
-- =============================================================
CREATE TABLE resenas (
    id_resena               INT             NOT NULL IDENTITY(1,1),
    id_juego                INT             NOT NULL,
    positivas               INT             NOT NULL DEFAULT 0,
    negativas               INT             NOT NULL DEFAULT 0,
    porcentaje_positivo     DECIMAL(5,2)    NOT NULL DEFAULT 0.00,
    descripcion_general     NVARCHAR(100)   NULL,

    CONSTRAINT PK_resenas                   PRIMARY KEY (id_resena),
    CONSTRAINT UQ_resenas_juego             UNIQUE      (id_juego),
    CONSTRAINT FK_resenas_juego             FOREIGN KEY (id_juego)
        REFERENCES juegos (id_juego)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT CK_resenas_positivas         CHECK (positivas >= 0),
    CONSTRAINT CK_resenas_negativas         CHECK (negativas >= 0),
    CONSTRAINT CK_resenas_porcentaje        CHECK (porcentaje_positivo BETWEEN 0.00 AND 100.00),
    CONSTRAINT CK_resenas_descripcion       CHECK (
        descripcion_general IN (
            'Overwhelmingly Positive',
            'Very Positive',
            'Positive',
            'Mostly Positive',
            'Mixed',
            'Mostly Negative',
            'Negative',
            'Very Negative',
            'Overwhelmingly Negative'
        ) OR descripcion_general IS NULL
    )
);
GO

-- =============================================================
-- INDICES adicionales para consultas frecuentes
-- =============================================================
CREATE INDEX IX_juegos_nombre
    ON juegos (nombre);

CREATE INDEX IX_juegos_desarrollador
    ON juegos (desarrollador);

CREATE INDEX IX_estadisticas_juego_fecha
    ON estadisticas (id_juego, fecha_registro DESC);

CREATE INDEX IX_resenas_porcentaje
    ON resenas (porcentaje_positivo DESC);
GO

-- =============================================================
-- Verificacion de objetos creados
-- =============================================================
SELECT
    t.name              AS tabla,
    c.name              AS columna,
    tp.name             AS tipo,
    c.max_length,
    c.is_nullable,
    c.column_id
FROM sys.tables      t
JOIN sys.columns     c  ON c.object_id  = t.object_id
JOIN sys.types       tp ON tp.user_type_id = c.user_type_id
ORDER BY t.name, c.column_id;
GO
