USE mdb;
SET NOCOUNT ON;

--------------------------------------------------------------------------------
-- Consulta de todos os logs dos chamados listados
--
-- Objetivo: retornar todos os registros da act_log relacionados aos chamados
-- informados na tabela temporária #Alvo, sem filtrar por tipo de log, descrição,
-- status, transferência, grupo ou A2B.
--
-- A consulta limita o resultado apenas aos chamados listados em #Alvo.
--------------------------------------------------------------------------------

DECLARE @HorasBrasilParaUTC int = 3;
DECLARE @Epoch datetime2(0) = '1970-01-01 00:00:00';

IF OBJECT_ID('tempdb..#Alvo') IS NOT NULL DROP TABLE #Alvo;
CREATE TABLE #Alvo (
    ref_num varchar(30) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY
);

-- Chamados sob investigação. Inclua/remova conforme necessário.
INSERT INTO #Alvo(ref_num) VALUES
    ('1687187'),
	('1687187');

SELECT
    r.ref_num AS SDM,
    DATEADD(HOUR, -@HorasBrasilParaUTC, DATEADD(SECOND, al.system_time, @Epoch)) AS QuandoBR,
    al.type AS Tipo,
    LTRIM(RTRIM(
        CASE
            WHEN (ISNULL(ct.first_name, N'') <> N'' OR ISNULL(ct.last_name, N'') <> N'')
                THEN CONCAT(ISNULL(ct.first_name, N''), N' ', ISNULL(ct.last_name, N''))
            WHEN ISNULL(ct.userid, N'') <> N'' THEN ct.userid
            ELSE N'N/A'
        END
    )) AS Analista,
    TRY_CONVERT(int, al.time_spent) AS TempoGastoSeg,
    CONVERT(nvarchar(max), al.description) AS Descricao,
    CONVERT(nvarchar(max), al.action_desc) AS AcaoDesc
FROM dbo.call_req AS r
JOIN #Alvo AS a
    ON a.ref_num COLLATE DATABASE_DEFAULT = r.ref_num COLLATE DATABASE_DEFAULT
JOIN dbo.act_log AS al
    ON al.call_req_id = r.persid
LEFT JOIN dbo.ca_contact AS ct
    ON ct.contact_uuid = al.analyst
ORDER BY
    r.ref_num,
    al.system_time;
