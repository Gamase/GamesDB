-- =============================================================
-- GamesDB -- Stored Procedures de Backup y Jobs en SQL Agent
-- SQL Server 2017+
-- RUTA BASE: C:\Proyectos\GamesDB\backups\
-- =============================================================


-- =============================================================
-- S T O R E D   P R O C E D U R E S   D E   B A C K U P
-- =============================================================

USE GamesDB;
GO

-- -------------------------------------------------------------
-- sp_backup_full
-- Backup completo con COMPRESSION y CHECKSUM.
-- Nombre: GamesDB_FULL_YYYYMMDD_HHMMSS.bak
-- -------------------------------------------------------------
IF OBJECT_ID('dbo.sp_backup_full', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_backup_full;
GO

CREATE PROCEDURE dbo.sp_backup_full
    @ruta_base NVARCHAR(500) = N'C:\Proyectos\GamesDB\backups\'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @timestamp  NVARCHAR(15)  = FORMAT(GETDATE(), 'yyyyMMdd_HHmmss');
    DECLARE @ruta       NVARCHAR(600) = @ruta_base + N'GamesDB_FULL_' + @timestamp + N'.bak';
    DECLARE @nombre     NVARCHAR(200) = N'GamesDB FULL ' + @timestamp;

    -- Crear carpeta si no existe (idempotente)
    EXEC master.dbo.xp_create_subdir @ruta_base;

    PRINT 'Iniciando backup FULL: ' + @ruta;

    BEGIN TRY
        BACKUP DATABASE GamesDB
        TO DISK = @ruta
        WITH
            NAME        = @nombre,
            DESCRIPTION = N'Backup completo automatico de GamesDB',
            COMPRESSION,
            CHECKSUM,
            STATS       = 10;

        PRINT 'Backup FULL completado: ' + @ruta;
    END TRY
    BEGIN CATCH
        DECLARE @msg NVARCHAR(500) =
            'sp_backup_full fallo: ' + ERROR_MESSAGE();
        RAISERROR(@msg, 16, 1);
    END CATCH;
END;
GO


-- -------------------------------------------------------------
-- sp_backup_differential
-- Backup diferencial respecto al ultimo FULL.
-- Nombre: GamesDB_DIFF_YYYYMMDD_HHMMSS.bak
-- Requiere al menos un backup FULL previo.
-- -------------------------------------------------------------
IF OBJECT_ID('dbo.sp_backup_differential', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_backup_differential;
GO

CREATE PROCEDURE dbo.sp_backup_differential
    @ruta_base NVARCHAR(500) = N'C:\Proyectos\GamesDB\backups\'
AS
BEGIN
    SET NOCOUNT ON;

    -- Verificar que exista al menos un backup FULL previo
    IF NOT EXISTS (
        SELECT 1 FROM msdb.dbo.backupset
        WHERE database_name = N'GamesDB'
          AND type = 'D'
    )
    BEGIN
        RAISERROR(
            'No existe un backup FULL previo de GamesDB. Ejecuta sp_backup_full antes del primer diferencial.',
            16, 1
        );
        RETURN;
    END;

    DECLARE @timestamp  NVARCHAR(15)  = FORMAT(GETDATE(), 'yyyyMMdd_HHmmss');
    DECLARE @ruta       NVARCHAR(600) = @ruta_base + N'GamesDB_DIFF_' + @timestamp + N'.bak';
    DECLARE @nombre     NVARCHAR(200) = N'GamesDB DIFF ' + @timestamp;

    EXEC master.dbo.xp_create_subdir @ruta_base;

    PRINT 'Iniciando backup DIFERENCIAL: ' + @ruta;

    BEGIN TRY
        BACKUP DATABASE GamesDB
        TO DISK = @ruta
        WITH
            DIFFERENTIAL,
            NAME        = @nombre,
            DESCRIPTION = N'Backup diferencial automatico de GamesDB',
            COMPRESSION,
            CHECKSUM,
            STATS       = 10;

        PRINT 'Backup DIFERENCIAL completado: ' + @ruta;
    END TRY
    BEGIN CATCH
        DECLARE @msg NVARCHAR(500) =
            'sp_backup_differential fallo: ' + ERROR_MESSAGE();
        RAISERROR(@msg, 16, 1);
    END CATCH;
END;
GO


-- -------------------------------------------------------------
-- sp_backup_log
-- Backup del transaction log.
-- Nombre: GamesDB_LOG_YYYYMMDD_HHMMSS.bak
-- Requiere modelo de recuperacion FULL o BULK_LOGGED.
-- -------------------------------------------------------------
IF OBJECT_ID('dbo.sp_backup_log', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_backup_log;
GO

CREATE PROCEDURE dbo.sp_backup_log
    @ruta_base NVARCHAR(500) = N'C:\Proyectos\GamesDB\backups\'
AS
BEGIN
    SET NOCOUNT ON;

    -- Verificar modelo de recuperacion
    IF EXISTS (
        SELECT 1 FROM sys.databases
        WHERE name = N'GamesDB'
          AND recovery_model_desc = N'SIMPLE'
    )
    BEGIN
        DECLARE @err_rec NVARCHAR(500) =
            'GamesDB usa recuperacion SIMPLE. Cambia a FULL o BULK_LOGGED: '
            + 'ALTER DATABASE GamesDB SET RECOVERY FULL';
        RAISERROR(@err_rec, 16, 1);
        RETURN;
    END;

    -- Verificar que exista al menos un backup FULL para iniciar la cadena
    IF NOT EXISTS (
        SELECT 1 FROM msdb.dbo.backupset
        WHERE database_name = N'GamesDB'
          AND type = 'D'
    )
    BEGIN
        RAISERROR(
            'No existe un backup FULL previo. Ejecuta sp_backup_full antes del primer backup de log.',
            16, 1
        );
        RETURN;
    END;

    DECLARE @timestamp  NVARCHAR(15)  = FORMAT(GETDATE(), 'yyyyMMdd_HHmmss');
    DECLARE @ruta       NVARCHAR(600) = @ruta_base + N'GamesDB_LOG_' + @timestamp + N'.bak';
    DECLARE @nombre     NVARCHAR(200) = N'GamesDB LOG ' + @timestamp;

    EXEC master.dbo.xp_create_subdir @ruta_base;

    PRINT 'Iniciando backup LOG: ' + @ruta;

    BEGIN TRY
        BACKUP LOG GamesDB
        TO DISK = @ruta
        WITH
            NAME        = @nombre,
            DESCRIPTION = N'Backup de transaction log automatico de GamesDB',
            COMPRESSION,
            CHECKSUM,
            STATS       = 10;

        PRINT 'Backup LOG completado: ' + @ruta;
    END TRY
    BEGIN CATCH
        DECLARE @msg NVARCHAR(500) =
            'sp_backup_log fallo: ' + ERROR_MESSAGE();
        RAISERROR(@msg, 16, 1);
    END CATCH;
END;
GO


-- -------------------------------------------------------------
-- sp_limpiar_backups
-- Elimina archivos .bak anteriores a @dias_retencion dias
-- usando xp_delete_file (procedimiento del subsistema de
-- mantenimiento de SQL Server, disenado para este uso).
-- -------------------------------------------------------------
IF OBJECT_ID('dbo.sp_limpiar_backups', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_limpiar_backups;
GO

CREATE PROCEDURE dbo.sp_limpiar_backups
    @ruta_base      NVARCHAR(500)  = N'C:\Proyectos\GamesDB\backups\',
    @dias_retencion INT            = 7
AS
BEGIN
    SET NOCOUNT ON;

    IF @dias_retencion < 1
    BEGIN
        RAISERROR('@dias_retencion debe ser >= 1.', 16, 1);
        RETURN;
    END;

    -- Fecha de corte en formato ISO 8601 que espera xp_delete_file
    DECLARE @fecha_corte NVARCHAR(20) =
        FORMAT(DATEADD(DAY, -@dias_retencion, GETDATE()), 'yyyy-MM-ddTHH:mm:ss');

    PRINT 'Eliminando backups .bak anteriores a: ' + @fecha_corte;

    -- xp_delete_file parametros:
    --   0            = tipo backup file
    --   @ruta_base   = carpeta (debe terminar en \)
    --   'bak'        = extension sin punto
    --   @fecha_corte = elimina archivos ANTERIORES a esta fecha
    --   0            = no incluir subcarpetas
    EXEC master.dbo.xp_delete_file
        0,
        @ruta_base,
        N'bak',
        @fecha_corte,
        0;

    PRINT 'Limpieza completada. Retencion: ' + CAST(@dias_retencion AS NVARCHAR) + ' dias.';
END;
GO


-- =============================================================
-- J O B S   E N   S Q L   S E R V E R   A G E N T
-- =============================================================

USE msdb;
GO

-- Categoria estandar de mantenimiento (existe por defecto en SQL Agent)
IF NOT EXISTS (
    SELECT 1 FROM msdb.dbo.syscategories
    WHERE name = N'Database Maintenance' AND category_class = 1
)
    EXEC msdb.dbo.sp_add_category
        @class = N'JOB',
        @type  = N'LOCAL',
        @name  = N'Database Maintenance';
GO


-- =============================================================
-- JOB 1: GamesDB - Backup Full
-- Diario a las 2:00 AM
-- =============================================================
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'GamesDB - Backup Full')
    EXEC msdb.dbo.sp_delete_job
        @job_name              = N'GamesDB - Backup Full',
        @delete_unused_schedule = 1;
GO

DECLARE @job_id UNIQUEIDENTIFIER;

EXEC msdb.dbo.sp_add_job
    @job_name         = N'GamesDB - Backup Full',
    @enabled          = 1,
    @description      = N'Backup completo de GamesDB. Diario a las 02:00 AM.',
    @category_name    = N'Database Maintenance',
    @owner_login_name = N'sa',
    @job_id           = @job_id OUTPUT;

EXEC msdb.dbo.sp_add_jobstep
    @job_id             = @job_id,
    @step_id            = 1,
    @step_name          = N'Ejecutar sp_backup_full',
    @subsystem          = N'TSQL',
    @database_name      = N'GamesDB',
    @command            = N'EXEC dbo.sp_backup_full;',
    @retry_attempts     = 1,
    @retry_interval     = 5,          -- minutos entre reintentos
    @on_success_action  = 1,          -- 1 = quit with success
    @on_fail_action     = 2;          -- 2 = quit with failure

EXEC msdb.dbo.sp_add_schedule
    @schedule_name      = N'GamesDB_Full_Diario_0200',
    @freq_type          = 4,          -- 4 = diario
    @freq_interval      = 1,          -- cada 1 dia
    @freq_subday_type   = 1,          -- 1 = una vez al dia
    @freq_subday_interval = 0,
    @active_start_time  = 020000;     -- 02:00:00

EXEC msdb.dbo.sp_attach_schedule
    @job_id        = @job_id,
    @schedule_name = N'GamesDB_Full_Diario_0200';

EXEC msdb.dbo.sp_add_jobserver
    @job_id      = @job_id,
    @server_name = N'(LOCAL)';
GO


-- =============================================================
-- JOB 2: GamesDB - Backup Diferencial
-- Cada 6 horas (00:00, 06:00, 12:00, 18:00)
-- =============================================================
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'GamesDB - Backup Diferencial')
    EXEC msdb.dbo.sp_delete_job
        @job_name              = N'GamesDB - Backup Diferencial',
        @delete_unused_schedule = 1;
GO

DECLARE @job_id UNIQUEIDENTIFIER;

EXEC msdb.dbo.sp_add_job
    @job_name         = N'GamesDB - Backup Diferencial',
    @enabled          = 1,
    @description      = N'Backup diferencial de GamesDB. Cada 6 horas.',
    @category_name    = N'Database Maintenance',
    @owner_login_name = N'sa',
    @job_id           = @job_id OUTPUT;

EXEC msdb.dbo.sp_add_jobstep
    @job_id             = @job_id,
    @step_id            = 1,
    @step_name          = N'Ejecutar sp_backup_differential',
    @subsystem          = N'TSQL',
    @database_name      = N'GamesDB',
    @command            = N'EXEC dbo.sp_backup_differential;',
    @retry_attempts     = 1,
    @retry_interval     = 5,
    @on_success_action  = 1,
    @on_fail_action     = 2;

EXEC msdb.dbo.sp_add_schedule
    @schedule_name        = N'GamesDB_Diff_Cada6H',
    @freq_type            = 4,        -- diario
    @freq_interval        = 1,
    @freq_subday_type     = 8,        -- 8 = horas
    @freq_subday_interval = 6,        -- cada 6 horas
    @active_start_time    = 000000;   -- empieza en medianoche

EXEC msdb.dbo.sp_attach_schedule
    @job_id        = @job_id,
    @schedule_name = N'GamesDB_Diff_Cada6H';

EXEC msdb.dbo.sp_add_jobserver
    @job_id      = @job_id,
    @server_name = N'(LOCAL)';
GO


-- =============================================================
-- JOB 3: GamesDB - Backup Log
-- Cada 30 minutos
-- =============================================================
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'GamesDB - Backup Log')
    EXEC msdb.dbo.sp_delete_job
        @job_name              = N'GamesDB - Backup Log',
        @delete_unused_schedule = 1;
GO

DECLARE @job_id UNIQUEIDENTIFIER;

EXEC msdb.dbo.sp_add_job
    @job_name         = N'GamesDB - Backup Log',
    @enabled          = 1,
    @description      = N'Backup del transaction log de GamesDB. Cada 30 minutos.',
    @category_name    = N'Database Maintenance',
    @owner_login_name = N'sa',
    @job_id           = @job_id OUTPUT;

EXEC msdb.dbo.sp_add_jobstep
    @job_id             = @job_id,
    @step_id            = 1,
    @step_name          = N'Ejecutar sp_backup_log',
    @subsystem          = N'TSQL',
    @database_name      = N'GamesDB',
    @command            = N'EXEC dbo.sp_backup_log;',
    @retry_attempts     = 1,
    @retry_interval     = 2,
    @on_success_action  = 1,
    @on_fail_action     = 2;

EXEC msdb.dbo.sp_add_schedule
    @schedule_name        = N'GamesDB_Log_Cada30M',
    @freq_type            = 4,        -- diario (se repite durante el dia)
    @freq_interval        = 1,
    @freq_subday_type     = 4,        -- 4 = minutos
    @freq_subday_interval = 30,       -- cada 30 minutos
    @active_start_time    = 000000;

EXEC msdb.dbo.sp_attach_schedule
    @job_id        = @job_id,
    @schedule_name = N'GamesDB_Log_Cada30M';

EXEC msdb.dbo.sp_add_jobserver
    @job_id      = @job_id,
    @server_name = N'(LOCAL)';
GO


-- =============================================================
-- JOB 4: GamesDB - Limpiar Backups
-- Diario a las 3:00 AM  (1 hora despues del FULL)
-- =============================================================
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'GamesDB - Limpiar Backups')
    EXEC msdb.dbo.sp_delete_job
        @job_name              = N'GamesDB - Limpiar Backups',
        @delete_unused_schedule = 1;
GO

DECLARE @job_id UNIQUEIDENTIFIER;

EXEC msdb.dbo.sp_add_job
    @job_name         = N'GamesDB - Limpiar Backups',
    @enabled          = 1,
    @description      = N'Elimina backups con mas de 7 dias. Diario a las 03:00 AM.',
    @category_name    = N'Database Maintenance',
    @owner_login_name = N'sa',
    @job_id           = @job_id OUTPUT;

EXEC msdb.dbo.sp_add_jobstep
    @job_id             = @job_id,
    @step_id            = 1,
    @step_name          = N'Ejecutar sp_limpiar_backups',
    @subsystem          = N'TSQL',
    @database_name      = N'GamesDB',
    @command            = N'EXEC dbo.sp_limpiar_backups @dias_retencion = 7;',
    @retry_attempts     = 0,
    @on_success_action  = 1,
    @on_fail_action     = 2;

EXEC msdb.dbo.sp_add_schedule
    @schedule_name      = N'GamesDB_Limpieza_Diario_0300',
    @freq_type          = 4,
    @freq_interval      = 1,
    @freq_subday_type   = 1,
    @freq_subday_interval = 0,
    @active_start_time  = 030000;     -- 03:00:00

EXEC msdb.dbo.sp_attach_schedule
    @job_id        = @job_id,
    @schedule_name = N'GamesDB_Limpieza_Diario_0300';

EXEC msdb.dbo.sp_add_jobserver
    @job_id      = @job_id,
    @server_name = N'(LOCAL)';
GO


-- =============================================================
-- Verificacion
-- =============================================================

USE GamesDB;
GO

-- SPs de backup creados
SELECT
    SCHEMA_NAME(o.schema_id) + '.' + o.name    AS procedimiento,
    o.create_date,
    o.modify_date
FROM sys.objects o
WHERE o.type = 'P'
  AND o.name IN (
      'sp_backup_full', 'sp_backup_differential',
      'sp_backup_log',  'sp_limpiar_backups'
  )
ORDER BY o.name;
GO

-- Jobs y schedules en SQL Agent
SELECT
    j.name                                      AS job,
    j.enabled,
    s.name                                      AS schedule,
    CASE s.freq_type
        WHEN 4 THEN 'Diario'
        WHEN 8 THEN 'Semanal'
        ELSE CAST(s.freq_type AS NVARCHAR)
    END                                         AS frecuencia,
    CASE s.freq_subday_type
        WHEN 1 THEN 'Una vez'
        WHEN 4 THEN 'Cada ' + CAST(s.freq_subday_interval AS NVARCHAR) + ' min'
        WHEN 8 THEN 'Cada ' + CAST(s.freq_subday_interval AS NVARCHAR) + ' h'
        ELSE '?'
    END                                         AS sub_frecuencia,
    RIGHT('0' + CAST(s.active_start_time / 10000     AS NVARCHAR), 2) + ':' +
    RIGHT('0' + CAST(s.active_start_time % 10000 / 100 AS NVARCHAR), 2)
                                                AS hora_inicio
FROM msdb.dbo.sysjobs           j
JOIN msdb.dbo.sysjobschedules  js ON js.job_id     = j.job_id
JOIN msdb.dbo.sysschedules      s  ON  s.schedule_id = js.schedule_id
WHERE j.name LIKE N'GamesDB - %'
ORDER BY j.name;
GO

-- Historial de backups registrado en msdb (muestra los ultimos 20)
SELECT TOP 20
    bs.database_name,
    CASE bs.type
        WHEN 'D' THEN 'FULL'
        WHEN 'I' THEN 'DIFERENCIAL'
        WHEN 'L' THEN 'LOG'
    END                                         AS tipo,
    bs.backup_start_date,
    bs.backup_finish_date,
    DATEDIFF(SECOND, bs.backup_start_date,
             bs.backup_finish_date)             AS duracion_seg,
    CAST(bs.backup_size / 1048576.0 AS DECIMAL(12,2))  AS size_mb,
    bmf.physical_device_name                    AS archivo
FROM msdb.dbo.backupset         bs
JOIN msdb.dbo.backupmediafamily bmf
    ON  bmf.media_set_id = bs.media_set_id
WHERE bs.database_name = N'GamesDB'
ORDER BY bs.backup_start_date DESC;
GO
