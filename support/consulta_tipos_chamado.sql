USE mdb;
SET NOCOUNT ON;

--------------------------------------------------------------------------------
-- Consulta Tipo - todos os tipos mapeados
--
-- Diferente da versão anterior, esta consulta não depende apenas dos tipos que
-- aparecem em dbo.call_req. Ela monta uma lista fixa dos tipos conhecidos e
-- faz LEFT JOIN com a contagem de chamados.
--
-- Resultado:
--   - I, R, P e C sempre aparecem, mesmo quando a quantidade for zero;
--   - qualquer tipo inesperado existente em dbo.call_req também aparece como
--     "Outro/Não mapeado".
--------------------------------------------------------------------------------

WITH Tipos AS (
    SELECT
        CONVERT(nvarchar(10), N'I') AS type_code,
        CONVERT(nvarchar(100), N'Incidente') AS type_nome,
        CONVERT(int, 1) AS ordem
    UNION ALL
    SELECT
        CONVERT(nvarchar(10), N'R') AS type_code,
        CONVERT(nvarchar(100), N'Solicitação') AS type_nome,
        CONVERT(int, 2) AS ordem
    UNION ALL
    SELECT
        CONVERT(nvarchar(10), N'P') AS type_code,
        CONVERT(nvarchar(100), N'Problema') AS type_nome,
        CONVERT(int, 3) AS ordem
    UNION ALL
    SELECT
        CONVERT(nvarchar(10), N'C') AS type_code,
        CONVERT(nvarchar(100), N'Mudança') AS type_nome,
        CONVERT(int, 4) AS ordem
),
Contagem AS (
    SELECT
        CONVERT(nvarchar(10), r.[type]) AS type_code,
        COUNT_BIG(*) AS qtd_chamados
    FROM dbo.call_req AS r
    GROUP BY
        r.[type]
),
Resultado AS (
    SELECT
        t.type_code,
        t.type_nome,
        COALESCE(c.qtd_chamados, 0) AS qtd_chamados,
        t.ordem
    FROM Tipos AS t
    LEFT JOIN Contagem AS c
        ON c.type_code = t.type_code

    UNION ALL

    SELECT
        ISNULL(c.type_code, N'NULO') AS type_code,
        CONCAT(N'Outro/Não mapeado: ', ISNULL(c.type_code, N'NULO')) AS type_nome,
        c.qtd_chamados,
        CONVERT(int, 999) AS ordem
    FROM Contagem AS c
    WHERE NOT EXISTS (
        SELECT 1
        FROM Tipos AS t
        WHERE t.type_code = c.type_code
    )
)
SELECT
    type_code,
    type_nome,
    qtd_chamados
FROM Resultado
ORDER BY
    ordem,
    type_code;
