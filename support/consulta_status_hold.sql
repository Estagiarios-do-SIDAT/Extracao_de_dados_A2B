USE mdb;

--------------------------------------------------------------------------------
-- Consulta de apoio: status x flag de hold (cr_stat.hold)
--
-- Mostra cada status do SDM e como ele entra na apuracao de tempo da Decision.
-- A regra vem do proprio produto (atributo "Stop Service Type Events"): ao entrar
-- num status com esse atributo, o relogio do SLA para. No banco esse atributo e a
-- coluna dbo.cr_stat.hold (0 ou 1).
--
--   hold = 1 -> SUSPENSO -> entra no Tempo Suspenso
--   hold = 0 -> ATIVO    -> entra no Tempo Total Decision
--
-- Serve para demonstrar o que a consulta considera em "Tempo Suspenso".
-- Referencia: decision/docs/tempo-decision-calculation.md (secao 2).
--------------------------------------------------------------------------------

-- [1] Todos os status e sua classificacao
SELECT
    s.sym                                                 AS [Status],
    s.code                                                AS [Codigo],
    s.hold                                                AS [hold],
    CASE WHEN s.hold = 1 THEN 'SUSPENSO' ELSE 'ATIVO' END AS [Classificacao],
    s.active                                              AS [Ativo (em uso)],
    s.del                                                 AS [Excluido]
FROM dbo.cr_stat AS s
ORDER BY
    s.hold   DESC,   -- primeiro os que contam como Tempo Suspenso
    s.active DESC,   -- depois os em uso antes dos legados
    s.sym;

-- [2] Somente os status que contam como Tempo Suspenso (hold = 1)
SELECT
    s.sym    AS [Status],
    s.code   AS [Codigo],
    s.active AS [Ativo (em uso)],
    s.del    AS [Excluido]
FROM dbo.cr_stat AS s
WHERE s.hold = 1
ORDER BY s.active DESC, s.sym;

-- [3] Somente os status de hold OPERACIONAIS (param o relogio de um chamado em
--     andamento): hold = 1, em uso e nao excluidos. Exclui os status finais
--     (Resolvido/Fechado/Cancelado), que tambem tem hold = 1 mas com active = 0.
SELECT
    s.sym    AS [Status],
    s.code   AS [Codigo]
FROM dbo.cr_stat AS s
WHERE s.hold = 1
  AND s.active = 1
  AND s.del = 0
ORDER BY s.sym;
