-- =============================================================
-- GamesDB -- Job: Sincronizar MySQL cada 30 minutos
-- Prerequisito: sp_sincronizar_mysql debe existir en GamesDB
--               y el linked server MySQL_GamesDB debe estar
--               configurado (ver cabecera de 02_vistas_tvf_sp.sql)
-- =============================================================

USE msdb;
GO

-- Eliminar job previo (y su schedule si no esta en uso)
IF EXISTS (
    SELECT 1 FROM msdb.dbo.sysjobs
    WHERE name = N'GamesDB - Sincronizar MySQL'
)
    EXEC msdb.dbo.sp_delete_job
        @job_name               = N'GamesDB - Sincronizar MySQL',
        @delete_unused_schedule = 1;
GO

DECLARE @job_id UNIQUEIDENTIFIER;

EXEC msdb.dbo.sp_add_job
    @job_name         = N'GamesDB - Sincronizar MySQL',
    @enabled          = 1,
    @description      = N'Sincronizacion incremental de GamesDB hacia MySQL via linked server MySQL_GamesDB. Cada 30 minutos.',
    @category_name    = N'Database Maintenance',
    @owner_login_name = N'sa',
    @job_id           = @job_id OUTPUT;

EXEC msdb.dbo.sp_add_jobstep
    @job_id            = @job_id,
    @step_id           = 1,
    @step_name         = N'Ejecutar sp_sincronizar_mysql INCREMENTAL',
    @subsystem         = N'TSQL',
    @database_name     = N'GamesDB',
    @command           = N'EXEC dbo.sp_sincronizar_mysql
    @linked_server = N''MySQL_GamesDB'',
    @modo          = N''INCREMENTAL'';',
    @retry_attempts    = 1,
    @retry_interval    = 3,        -- minutos entre reintentos
    @on_success_action = 1,        -- 1 = quit with success
    @on_fail_action    = 2;        -- 2 = quit with failure

EXEC msdb.dbo.sp_add_schedule
    @schedule_name        = N'GamesDB_SyncMySQL_Cada30M',
    @freq_type            = 4,     -- diario (repeticion sub-diaria)
    @freq_interval        = 1,
    @freq_subday_type     = 4,     -- 4 = minutos
    @freq_subday_interval = 30,    -- cada 30 minutos
    @active_start_time    = 000000;

EXEC msdb.dbo.sp_attach_schedule
    @job_id        = @job_id,
    @schedule_name = N'GamesDB_SyncMySQL_Cada30M';

EXEC msdb.dbo.sp_add_jobserver
    @job_id      = @job_id,
    @server_name = N'(LOCAL)';
GO


-- =============================================================
-- Verificacion
-- =============================================================

-- Job, paso y schedule
SELECT
    j.name                                          AS job,
    j.enabled,
    j.description,
    js.step_id,
    js.step_name,
    js.database_name,
    js.command,
    js.retry_attempts,
    js.retry_interval                               AS retry_min
FROM msdb.dbo.sysjobs      j
JOIN msdb.dbo.sysjobsteps  js ON js.job_id = j.job_id
WHERE j.name = N'GamesDB - Sincronizar MySQL';

-- Schedule adjunto
SELECT
    j.name                                          AS job,
    s.name                                          AS schedule,
    CASE s.freq_subday_type
        WHEN 4 THEN 'Cada ' + CAST(s.freq_subday_interval AS NVARCHAR) + ' min'
        WHEN 8 THEN 'Cada ' + CAST(s.freq_subday_interval AS NVARCHAR) + ' h'
        ELSE 'Una vez'
    END                                             AS frecuencia,
    s.enabled                                       AS schedule_activo
FROM msdb.dbo.sysjobs          j
JOIN msdb.dbo.sysjobschedules  js ON js.job_id      = j.job_id
JOIN msdb.dbo.sysschedules      s  ON  s.schedule_id = js.schedule_id
WHERE j.name = N'GamesDB - Sincronizar MySQL';
GO
