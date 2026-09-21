# Consulta consolidada do Power BI — Protect4

Documentação da fonte de dados usada no painel de FAIA e FARC da Protect4.

Escrita para quem vai **usar** o painel, não para quem escreveu o SQL.

---

## Índice

1. [Finalidade](#1-finalidade)
2. [Consultas de referência](#2-consultas-de-referência)
3. [Como usar no Power BI](#3-como-usar-no-power-bi)
4. [Power BI e SQL Server](#4-power-bi-e-sql-server)
5. [Período da consulta](#5-período-da-consulta)
6. [Colunas compartilhadas](#6-colunas-compartilhadas)
7. [Colunas do FAIA](#7-colunas-do-faia)
8. [Colunas do FARC](#8-colunas-do-farc)
9. [Regras básicas](#9-regras-básicas)
10. [Feriados e pontos facultativos](#10-feriados-e-pontos-facultativos)
11. [Conferência](#11-conferência)
12. [Limitações](#12-limitações)
13. [Manutenção no Power Query](#13-manutenção-no-power-query)

Há uma versão desta documentação em HTML, para exibir dentro do painel no visual
**HTML Content**: `docs/documentacao-powerbi-a2b.html`. Ela deriva deste
arquivo; se os dois divergirem, **vale este**.

---

## 1. Finalidade

A consulta reúne, em **uma linha por chamado**:

```text
dados do chamado
resultado do FAIA
resultado do FARC
colunas auxiliares para conferência
```

Antes dela era preciso rodar duas consultas separadas e cruzar os resultados à mão. Aqui os dois indicadores do mesmo chamado chegam juntos, na mesma linha, prontos para o painel.

Ela devolve **um único resultado**. Não traz tabelas de diagnóstico nem resultados intermediários.

---

## 2. Consultas de referência

As **referências técnicas** de cada cálculo continuam sendo as consultas individuais:

```text
queries/consulta_faia_a2b_protect4.sql
queries/consulta_farc_a2b_protect4.sql
```

Elas têm **parametrização própria de período** (`@InicioBrasil` / `@FimBrasil`, digitados no arquivo) e **não** usam a regra de 12 ciclos: essa regra é exclusiva da consulta consolidada do Power BI.

Elas não foram substituídas. Quando houver dúvida sobre **como** um número é calculado, a resposta está nelas — e nos documentos [faia-calculation.md](faia-calculation.md) e [farc-calculation.md](farc-calculation.md).

A consulta do Power BI **não reimplementa** nenhum cálculo: ela usa os mesmos dois motores, lado a lado, e junta os resultados no fim.

---

## 3. Como usar no Power BI

1. **Obter dados → SQL Server.**
2. Informe o servidor e o banco de dados **`mdb`**.
3. Escolha o modo **Importação**.
4. Abra **Opções avançadas** e cole o conteúdo inteiro de `consulta_faia_farc_power_bi.sql` no campo **Instrução SQL**.
5. Deixe **"Adicionar colunas de relação" desmarcado**.
6. Carregue e, na primeira vez, confira a quantidade de chamados (ver [seção 11](#11-conferência)).
7. Nas próximas vezes, basta **Atualizar**: o período se ajusta sozinho (ver [seção 5](#5-período-da-consulta)).
8. Na primeira atualização depois de qualquer mudança no texto SQL, o Power BI pede para **aprovar a execução da consulta nativa**. Isso é esperado.

Não é preciso ajustar datas a cada mês. Não é preciso rodar nenhum script antes.

---

## 4. Power BI e SQL Server

### Quem executa a consulta

O arquivo é **T-SQL puro**. Não é Power Query M, não é DAX e não está encapsulado em `Value.NativeQuery`.

```text
A consulta é usada pelo Power BI, mas é executada pelo SQL Server.
O Power BI envia o script pelo conector e importa o resultado.
```

Ou seja: o Power BI **não calcula nada**. Ele abre a conexão, manda o texto do script, espera e recebe o result set final. Quem compila, otimiza e executa é o SQL Server.

A consequência é direta: **em condições equivalentes, o mesmo script deve rodar integralmente no SSMS**. Se ele funciona no Power BI e não no SSMS, isso não é uma característica do Power BI — é uma diferença de **contexto de execução**, e ela precisa ser identificada.

### O banco de dados precisa ser o `mdb`

Esta é a diferença de contexto que já causou problema, e a razão de a consulta ter sido corrigida.

Todas as referências a tabelas no script são de **duas partes** (`dbo.call_req`, `dbo.act_log`, `dbo.cr_stat`, `dbo.pri`, `dbo.prob_ctg`, `dbo.ca_contact`, `dbo.audit_log`, `dbo.View_Audit_Group`). Nomes de duas partes se resolvem sempre no **banco atual da sessão**.

| Cliente | Como o banco é definido | Resultado |
|---|---|---|
| **Power BI** | O conector recebe `mdb` na própria conexão | Roda sempre no banco certo |
| **SSMS** | A janela nova abre no **banco padrão do login**, em geral o `master` | Sem `USE mdb`, falha antes de executar |

Fora do `mdb`, o lote inteiro falha na **compilação**, com `Msg 208 — Invalid object name`. Como o script é um lote único, **nada roda e nenhuma linha é devolvida**.

O script começa com `USE mdb;`, o mesmo padrão das outras consultas. Com isso ele não depende do cliente para escolher o banco. No Power BI a instrução é inofensiva — a conexão já aponta para o `mdb`.

### Como rodar no SSMS

1. Conecte no mesmo servidor usado pelo Power BI.
2. Confirme `mdb` na caixa de seleção de banco de dados (o `USE mdb;` do script já cobre isso, mas a caixa evita dúvida).
3. Abra o arquivo **inteiro** e execute **sem selecionar trecho**. Executar só um pedaço quebra a consulta: as tabelas temporárias dos blocos anteriores não existiriam.
4. Use as **mesmas credenciais ou permissões equivalentes** às do Power BI — basta leitura nas tabelas acima e permissão de criar tabela temporária em `tempdb`.
5. Não é preciso sessão limpa. As 45 tabelas temporárias têm nomes exclusivos e cada bloco começa com `IF OBJECT_ID(...) DROP TABLE`, então a consulta roda duas vezes seguidas na mesma sessão e também depois das consultas individuais da Protect4 e da Decision.

### Se der erro no SSMS

| Erro | Causa provável | O que fazer |
|---|---|---|
| `Msg 208 — Invalid object name 'dbo.call_req'` | Sessão em outro banco | Selecionar `mdb`; conferir se o `USE mdb;` do topo foi colado junto |
| `Msg 207 — Invalid column name` | Tabela temporária antiga, de outra versão do script, ainda viva na sessão | Abrir sessão nova e repetir; se persistir, é defeito do arquivo e deve ser investigado |
| `Msg 1088 / objeto #... não existe` | Foi executado só um trecho selecionado | Executar o arquivo inteiro |
| Nada retorna / demora demais | Volume ou bloqueio | Aguardar; comparar com o tempo de atualização no Power BI |

Ao relatar um problema, informe sempre: **cliente** (Power BI ou SSMS), **banco atual**, **usuário**, **mensagem de erro completa com o número da linha** e se o arquivo foi executado inteiro.

---

## 5. Período da consulta

O período é **automático**. Não há data para editar a cada mês. **Esta seção vale para a consulta consolidada do Power BI** (`powerbi/consulta_faia_farc_power_bi.sql`); as consultas individuais têm período próprio, digitado no arquivo — ver [seção 2](#2-consultas-de-referência).

- No relatório Power BI, a consulta consolidada apresenta os **12 ciclos mais recentes** da Protect4 — cerca de um ano.
- Cada ciclo compreende o período iniciado às **00:00:00 do dia 24** e encerrado ao **final do dia 23 do mês seguinte**.
- O ciclo **em andamento não entra** — só entram ciclos já fechados.
- A quantidade de ciclos é controlada por um único número, `@PBI_QuantidadeCiclos`, que é a **primeira instrução** do SQL. O padrão é `12`.
- As datas são interpretadas no **horário do Brasil (GMT-3)**. O SDM grava em UTC; a consulta faz a conversão.
- Na consulta, essa regra é implementada como intervalo **fechado no início e aberto no fim** — `>= dia 24` e `< dia 24 do mês seguinte` —, o que evita perder registros com frações de segundo no encerramento do dia 23. A janela inteira termina, exclusiva, às 00:00 do dia 24 do ciclo em andamento.

**Exemplo, atualizando em 18/09/2026** (antes do dia 24, então o ciclo em andamento começou em 24/08):

```text
janela = 24/08/2025 00:00  até  24/08/2026 00:00 (exclusivo)
ciclos = 24/08/2025–23/09/2025  …  24/07/2026–23/08/2026   (12 ciclos)
ciclo em andamento, EXCLUÍDO:    24/08/2026–23/09/2026
```

No dia 24 a janela avança um ciclo inteiro, sozinha.

**O filtro usa a data de fechamento do chamado** (`close_date`). Ou seja: entra no resultado todo chamado que **fechou** dentro da janela dos ciclos carregados.

**Mudar a quantidade de ciclos.** Troca-se só o número de `@PBI_QuantidadeCiclos` — o passo a passo no Power Query está na [seção 13](#13-manutenção-no-power-query):

| Cobertura desejada | Linha do SQL |
|---|---|
| 6 ciclos | `DECLARE @PBI_QuantidadeCiclos int = 6;` |
| 12 ciclos (padrão) | `DECLARE @PBI_QuantidadeCiclos int = 12;` |
| 18 ciclos | `DECLARE @PBI_QuantidadeCiclos int = 18;` |

Voltar N meses a partir de um dia 24 cai sempre em outro dia 24, então a janela começa exatamente no início de um ciclo, qualquer que seja o número. Nenhuma regra de negócio depende dele. Antes de aumentar, confira se os feriados dos ciclos mais antigos estão cadastrados — ver [seção 10](#10-feriados-e-pontos-facultativos).

Um ponto importante:

> O período **seleciona quais chamados entram**. Ele **não corta** os tempos calculados.

Se um chamado fechou dentro da janela mas foi aberto antes dela, o FAIA e o FARC dele são calculados sobre a vida inteira do chamado, e não só sobre o pedaço que caiu dentro do período.

---

## 6. Colunas compartilhadas

São os dados do próprio chamado. Aparecem **uma vez só**, mesmo que os dois indicadores as tivessem.

| Coluna | Significado | Origem | Formato |
|---|---|---|---|
| `SDM` | Número do chamado | `call_req.ref_num` | texto |
| `Tipo Chamado` | Incidente, Solicitação, Problema ou Mudança | `call_req.type` | texto |
| `Severidade` | De `1 - Máxima` a `5 - Mínima` | prioridade do chamado | texto |
| `Status` | Status final do chamado | `cr_stat` | texto |
| `Categoria` | Categoria do SDM (`A2B.*`) | `prob_ctg` | texto |
| `Responsável Abertura` | Quem abriu | `ca_contact` | texto |
| `Responsável Atendimento` | Quem estava atribuído | `ca_contact` | texto |
| `Resumo` | Título do chamado | `call_req.summary` | texto |
| `Data Abertura` | Início da contagem: entrada do chamado no grupo A2B | log de transferência de grupo, com abertura como fallback | data e hora |
| `Data Captura` | Primeira ida do status para "Em andamento" | `act_log` | data e hora |
| `Data de Fechamento` | Fechamento do chamado | `call_req.close_date` | data e hora |
| `Dia da Semana do Fechamento` | Segunda-feira a Domingo | calculado | texto |
| `Indicador Reabertura` | `Sim` / `Não` | `act_log` | texto |
| `Acordo Prazo` | Reservado, sempre `-` | fixo | texto |
| `Acordo Qualidade` | Reservado, sempre `-` | fixo | texto |
| `Justificativa` | Reservado, sempre `-` | fixo | texto |

---

## 7. Colunas do FAIA

O FAIA mede **quanto se esperou até alguém começar a atender**.

| Coluna | Significado | Formato |
|---|---|---|
| `Tempo Primeiro Atendimento` | Tempo da entrada no grupo até a captura | texto `HH:MM:SS` |
| `Tempo Primeiro Atendimento (s)` | O mesmo tempo, **em segundos** | número |
| `Primeiro Atendimento Excedido` | Quanto passou da meta | texto `HH:MM:SS` |
| `Primeiro Atendimento Excedido (s)` | O mesmo excedente, **em segundos** | número |
| `Meta Primeiro Atendimento` | `Atende` ou `Não Atende` | texto |
| `nHR_FAIA` | Horas de atraso, proporcionais | número com 2 casas |
| `FAIA` | `nHR_FAIA` × fator **0,1** | número com 2 casas |
| `Hora da Abertura` | Só a hora da entrada no grupo | texto `HH:MM:SS` |
| `Hora da Captura` | Só a hora da captura | texto `HH:MM:SS` |
| `Dia da Semana da Abertura` | Segunda-feira a Domingo | texto |
| `Dia da Semana da Captura` | Segunda-feira a Domingo | texto |
| `Quantidade de Logs` | Total de registros de `act_log` do chamado | número |

Observações:

- **Use as colunas `(s)` em medidas.** As colunas `HH:MM:SS` são texto e servem para leitura; elas não somam nem comparam corretamente.
- `Hora da Captura` usa exatamente o mesmo marco de `Data Captura`. Chamado **sem captura** fica com esses campos vazios — não dá erro.
- `Quantidade de Logs` conta **todos** os tipos de log (INIT, ST, TR, SOLN, CL, LOG, FLD, SRVY_SENT, ATTACHTDOC e outros). Não é a contagem dos logs que entram no cálculo. Chamado sem log nenhum recebe **0**.
- A meta em si (15 min, 60 min, 240 min ou 720 min, conforme a severidade) não é devolvida como coluna; o que aparece é o resultado da comparação, em `Meta Primeiro Atendimento`.

---

## 8. Colunas do FARC

O FARC mede **quanto tempo se trabalhou no chamado até resolvê-lo**.

| Coluna | Significado | Formato |
|---|---|---|
| `Tempo de Atendimento` | Tempo ativo somado em todas as janelas de posse do A2B | texto `HH:MM:SS` |
| `Tempo de Atendimento (s)` | O mesmo tempo, **em segundos** | número |
| `Tempo Atendimento Excedido` | Quanto passou da meta de resolução | texto `HH:MM:SS` |
| `Tempo Atendimento Excedido (s)` | O mesmo excedente, **em segundos** | número |
| `Meta Atendimento` | `Atende` ou `Não Atende` | texto |
| `nHR_FARC` | Horas de atraso, proporcionais | número com 2 casas |
| `FARC` | `nHR_FARC` × fator **0,3** | número com 2 casas |

Repare que o **fator do FARC (0,3) é diferente do fator do FAIA (0,1)**. São indicadores distintos, com penalidades distintas.

---

## 9. Regras básicas

**FAIA e FARC não medem a mesma coisa.**

- **FAIA** olha só o **começo**: da entrada do chamado no grupo A2B até a primeira ida para "Em andamento". É um ponto no tempo.
- **FARC** olha a **duração do trabalho**: soma o tempo em que o chamado esteve efetivamente ativo com o A2B, até a resolução.

Um chamado pode atender o FAIA (alguém pegou em 5 minutos) e estourar o FARC (só ficou pronto três dias depois). E vice-versa.

**Calendário, conforme a severidade:**

- **P1 e P2** contam **corrido**: 24 horas por dia, incluindo fim de semana e feriado.
- **P3, P4 e P5** contam **comercial**: só de segunda a sexta, das **08:00 às 20:00**.
- No comercial, **feriados e pontos facultativos do TCU não contam**. Estão cadastrados dentro da própria consulta, em duas listas: feriados fixos (que se repetem todo ano) e feriados móveis/pontos facultativos (por data).

**Entrada no grupo, posse e reposse:**

- A contagem **não começa na abertura do chamado no SDM**, e sim quando ele entra na posse do grupo **Fornecedores - A2B**. Se nasceu no grupo, aí sim vale a abertura.
- **Posse** é o período em que o chamado esteve com o grupo A2B.
- **Reposse** é quando o chamado sai do grupo e depois volta. Nesse caso existem várias janelas de posse, e o FARC **soma todas** — não só a última. Tempo que o chamado passou em outro grupo não conta.

**Uma linha por chamado:**

- Cada chamado aparece **uma única vez**.
- As tabelas que têm vários registros por chamado (como os logs) são **agregadas antes** de serem juntadas ao resultado, então elas não multiplicam linhas.
- O FAIA e o FARC são unidos pela chave interna do chamado, não pelo texto do SDM.
- Os dois indicadores têm escopos ligeiramente diferentes: o FAIA exige que o chamado **encerre** no grupo A2B, o FARC não. Por isso a junção preserva os dois lados. Um chamado que exista só para o FARC aparece com as colunas do FAIA **vazias** — ele não some do resultado.

---

## 10. Feriados e pontos facultativos

A consulta tem, dentro dela mesma, a lista de datas que **não** são dias úteis. Ela é usada só no **calendário comercial** (P3, P4 e P5). Chamados **P1 e P2 contam corrido** e ignoram essa lista por completo.

São **duas** tabelas, e o FAIA e o FARC usam **as mesmas duas** — não existe um calendário para cada indicador:

| Estrutura | O que guarda | Formato |
|---|---|---|
| `#PBI_FeriadosFixos` | Feriados que caem sempre no mesmo dia, todo ano | `'MM-DD'` — ex.: `'12-25'` |
| `#PBI_FeriadosPorData` | Feriados móveis e pontos facultativos do TCU | `'AAAA-MM-DD'` — ex.: `'2026-06-05'` |

A diferença é só essa: o que se repete todo ano entra **uma vez** em `#PBI_FeriadosFixos` e vale para sempre; o que muda de data a cada ano (Carnaval, Páscoa, emendas) entra em `#PBI_FeriadosPorData`, **ano a ano**.

O que entra em cada lista:

- **feriados nacionais fixos** — Confraternização Universal, Tiradentes, Dia do Trabalho, Independência, Nossa Senhora Aparecida, Finados, Proclamação da República, Consciência Negra e Natal;
- **feriados móveis** — Carnaval, Paixão de Cristo, Páscoa, Corpus Christi;
- **pontos facultativos do TCU** — emendas de feriado, véspera de Natal e de Ano-Novo, e os dias de Carnaval e Quarta-Feira de Cinzas.

**Sábados e domingos não devem ser cadastrados.** A consulta já os descarta sozinha, pelo dia da semana. Cadastrar um fim de semana não muda o resultado, só polui a lista.

**Fonte das datas.** Só fonte **oficial do TCU**: a portaria anual do Presidente do TCU que "divulga os feriados nacionais e define os dias de ponto facultativo" do ano, publicada no Boletim do TCU, **e todas as portarias que a alterarem**. Consulte em `pesquisa.apps.tcu.gov.br`, base **Normas**: a ficha da portaria anual lista, em "Alterada por", as alterações. Não use calendário civil genérico nem de outro órgão.

### Como atualizar

1. Abra a consulta `consulta_faia_farc_power_bi.sql`.
2. Localize o bloco `[S.2] Feriados e pontos facultativos`, com as tabelas `#PBI_FeriadosFixos` e `#PBI_FeriadosPorData`.
3. Acrescente as novas datas no mesmo formato já usado, num `INSERT INTO ... VALUES`.
4. Não inclua sábados e domingos — já são tratados automaticamente.
5. Não repita uma data já cadastrada. As duas tabelas têm chave primária, então uma data duplicada faz a consulta **falhar** na execução.
6. Cadastre os feriados e pontos facultativos **antes** de atualizar o período correspondente no Power BI.
7. Salve o SQL e valide um chamado P3/P4/P5 que atravesse a nova data.

Uma linha de data específica tem este formato — o exemplo é uma data que já está cadastrada:

```sql
    ('2026-06-05', N'Ponto facultativo - emenda após Corpus Christi'),
```

A última linha de cada `VALUES` termina em `;`, não em vírgula. Registre num comentário a portaria de origem.

Um feriado fixo entraria na outra tabela, sem ano, no formato `('MM-DD', N'descrição')`.

> **Manutenção anual.** Os feriados fixos já estão prontos e não precisam de nada. O que precisa de atenção **todo ano** é `#PBI_FeriadosPorData`: as datas móveis e os pontos facultativos do TCU de cada ano coberto pela janela. No fim do bloco já existe um comentário reservando o lugar de 2027.

**Situação atual do cadastro.** `#PBI_FeriadosPorData` cobre a janela de 12 ciclos: os pontos facultativos de 2025 a partir de outubro e **2026 completo**, conferidos contra as portarias do TCU.

| Ano | Portaria anual | Alterações | Datas por data específica no painel |
|---|---|---|---|
| 2025 | Portaria-TCU nº 10, de 13/01/2025 | nº 67, nº 157 e nº 176 de 2025 | 27/10, 21/11, 24/12, 26/12, 31/12 |
| 2026 | Portaria-TCU nº 1, de 08/01/2026 | nº 93 de 2026 | 02/01, 16–18/02, 02/04, 03/04, 05/04, 20/04, 04/06, 05/06, 29/06, 28/10, 24/12, 31/12 |

O PDF da portaria de 2026 guardado em `Documentos e Relatórios` é a versão **original**: a data de 29/06/2026 veio depois, pela Portaria nº 93/2026, e não aparece nele. As datas de 2025 anteriores a outubro não estão cadastradas porque nenhum chamado da janela padrão passa por elas.

As consultas individuais (`consulta_faia_a2b_protect4.sql` e `consulta_farc_a2b_protect4.sql`) têm as mesmas duas listas, com os nomes `#FeriadosFixos` e `#FeriadosPorData`. Ao incluir uma data nova, inclua **nas três**, senão os números do painel e os das consultas de referência passam a divergir.

---

## 11. Conferência

Depois de carregar, vale conferir:

**1. Não há chamado duplicado.** Esta é a checagem mais importante. Rode no SQL Server, em separado (não altere a consulta do painel para incluir isso):

```sql
SELECT
    COUNT(*)             AS total_linhas,
    COUNT(DISTINCT SDM)  AS total_sdms
FROM resultado;
```

```text
COUNT(*) deve ser igual a COUNT(DISTINCT SDM)
```

Se os dois números forem diferentes, existe duplicidade e o resultado não deve ser usado.

**2. Quantidade de linhas.** Compare o total com a atualização anterior. A janela só muda no dia 24, quando avança um ciclo inteiro; fora disso, o total deve ser estável. Uma variação grande merece investigação.

**3. Datas.** `Data Abertura` deve ser sempre menor ou igual a `Data Captura`, que deve ser menor ou igual a `Data de Fechamento`. Chamados sem captura ficam com `Data Captura` vazia — isso é normal.

**4. Quantidade de logs.** Deve ser sempre maior que zero para chamados que tiveram movimentação. Zero em massa indica problema.

**5. `nHR_FAIA` e `nHR_FARC`.** Devem aparecer **com casas decimais**. Se você vir só números inteiros, algo está errado: eles são proporcionais, não arredondados para cima. Um atraso de 1h30 tem que aparecer como `1,50`, nunca como `2`.

**6. `FAIA` e `FARC`.** Confira a proporção contra o `nHR` correspondente: `FAIA = nHR_FAIA × 0,1` e `FARC = nHR_FARC × 0,3`.

**7. Tipos de chamado.** Devem aparecer `Incidente`, `Solicitação` e `Problema`. Se `Problema` não aparecer nunca, confirme se realmente não houve nenhum no período.

---

## 12. Limitações

**Validado no código** (leitura e conferência estática do SQL):

- a consulta devolve um único resultado, sem `GO` e sem blocos de diagnóstico;
- todos os nomes de coluna são únicos;
- todas as tabelas temporárias são criadas antes de serem usadas;
- os nomes das temporárias não colidem com os das consultas individuais da Protect4 nem com os da Decision, então dá para rodar tudo na mesma sessão;
- `nHR_FAIA` e `nHR_FARC` usam `decimal(18,2)` e divisão proporcional, sem `CEILING`;
- as tabelas que poderiam multiplicar linhas são agregadas antes da junção final;
- FAIA e FARC são unidos pela chave interna do chamado;
- o script é T-SQL puro, um único lote, e começa com `USE mdb;`, portanto **não depende do cliente** para escolher o banco (ver [seção 4](#4-power-bi-e-sql-server)).

**Validado em execução no SQL Server** (2026-07-31):

- a consulta **executa com sucesso** no SQL Server após a inclusão do `USE mdb;`;
- o `Msg 208 — Invalid object name` **não ocorre mais**, e a causa da diferença Power BI × SSMS está encerrada.

**Pendente de validação no SQL Server** — nada abaixo foi conferido ainda:

- a execução em sessão limpa, duas vezes na mesma sessão e depois das consultas individuais;
- a conferência `COUNT(*) = COUNT(DISTINCT SDM)` com dados reais;
- a comparação dos números desta consulta com os das duas consultas individuais, chamado a chamado;
- o comportamento de chamados do tipo `Problema`, que nunca foram conferidos no banco;
- chamados com reposse (várias janelas de posse) e chamados sem captura;
- a contagem de logs contra a `act_log` real.

**Validado em execução no SQL Server** (2026-09-18) — cobertura de 12 ciclos:

- a janela vai de `24/08/2025` a `24/08/2026` exclusivo, medida em 18/09/2026;
- 2.410 linhas e 2.410 SDMs distintos, sem duplicidade;
- três execuções seguidas devolveram **resultado idêntico**: eventos gravados no mesmo segundo são ordenados por `act_log.id`, o que torna o FARC reproduzível;
- o FARC individual e o painel devolvem os mesmos `Tempo de Atendimento`, `Meta`, `nHR_FARC` e `FARC` nos 234 chamados do ciclo em comum.

**Limitações conhecidas:**

- os pontos facultativos de **2027 ainda não estão cadastrados**. A partir de janeiro de 2027 o calendário comercial ficará incompleto até que sejam incluídos.
- o FAIA e o FARC individuais (`queries/`) mantêm listas próprias de feriados. A do FAIA individual não tem `2025-12-24` e `2025-12-31`, presentes nas outras duas; um chamado comercial que atravesse essas datas pode ter FAIA ligeiramente diferente entre as duas consultas.
- nas colunas compartilhadas `Data Abertura` e `Data Captura`, o painel usa o valor da metade FAIA, que difere do FARC individual em alguns chamados — 9 dos 234 do ciclo 24/03–23/04/2026. As colunas do FARC coincidem nos 234.
- a regra de arredondamento (proporcional, em vez de "hora ou fração") **ainda não foi confirmada contra o edital**. Se o edital exigir "hora ou fração", os quatro indicadores do projeto precisarão ser revistos.
- o calendário de feriados desta consulta inclui `2025-12-24` e `2025-12-31`, que **não** estão na consulta individual do FAIA. Enquanto essa diferença existir, um chamado cuja janela comercial toque essas duas datas pode ter FAIA ligeiramente diferente entre as duas consultas.

---

## 13. Manutenção no Power Query

O texto SQL da consulta fica guardado na etapa **Fonte** do Power Query. É ali
que se muda a quantidade de ciclos e onde se cola a consulta depois de mexer
nos feriados.

### Onde fica o texto SQL

1. No Power BI Desktop: **Página Inicial → Transformar dados**. Abre o Power Query.
2. No painel **Consultas**, à esquerda, selecione a consulta da A2B.
3. No painel **Configurações da consulta**, à direita, em **Etapas aplicadas**, clique na **engrenagem** da etapa **Fonte**.
4. Abre a janela **Banco de dados SQL Server**. Em **Opções avançadas**, o campo **Instrução SQL** contém a consulta inteira.
5. Depois de editar: **OK → Fechar e aplicar**. Na primeira atualização o Power BI pede para **aprovar a consulta nativa** — aprove.

> Não existe um parâmetro do Power BI separado: a quantidade de ciclos é uma linha do próprio SQL. Montar o SQL por concatenação em M para expor um parâmetro faria a engrenagem da etapa Fonte deixar de mostrar o texto editável, e o painel passaria a depender de código M que não está versionado neste repositório.

### Mudar a quantidade de ciclos

A primeira instrução do SQL, logo no topo da caixa **Instrução SQL**, é:

```sql
DECLARE @PBI_QuantidadeCiclos int = 12;
```

1. Abra a etapa **Fonte** como acima.
2. Troque `12` pelo número de ciclos — por exemplo `6` ou `18`.
3. **OK → Fechar e aplicar**, aprove a consulta nativa e atualize.

É o único número que muda. A regra do ciclo — do dia 24 até o final do dia 23
do mês seguinte — não depende dele.

A consulta usada pelo painel fica incorporada ao próprio relatório, então a
troca vale a partir da próxima atualização. Existe um repositório interno, usado
para versionamento e manutenção técnica, onde a mesma alteração é registrada
pela equipe responsável quando a cobertura muda em definitivo.

### Atualizar feriados

O bloco `[S.2] Feriados e pontos facultativos` fica no meio de um texto longo,
e a caixa **Instrução SQL** não tem busca. O caminho seguro é editar o
**arquivo** e colar de volta:

1. Confirme a data na fonte oficial do TCU (seção 10).
2. Abra `powerbi/consulta_faia_farc_power_bi.sql` num editor e procure `[S.2]`.
3. **Adicionar:** inclua a linha na tabela certa — `#PBI_FeriadosFixos` (`'MM-DD'`) ou `#PBI_FeriadosPorData` (`'AAAA-MM-DD'`).
4. **Corrigir:** edite a data ou a descrição na linha existente.
5. **Remover:** apague a linha inteira e confira a vírgula da linha anterior.
6. As consultas de referência, `queries/consulta_faia_a2b_protect4.sql` e `queries/consulta_farc_a2b_protect4.sql`, têm listas próprias (`#FeriadosFixos` e `#FeriadosPorData`). Elas precisam ficar iguais à do painel, senão os números divergem.
7. Copie o arquivo do Power BI **inteiro** e cole no campo **Instrução SQL** da etapa **Fonte**, substituindo o texto anterior.
8. **OK → Fechar e aplicar**, aprove a consulta nativa e **atualize**.

**Cuidados.**

- Cada data aparece **uma vez só** por tabela. Uma data repetida faz a atualização falhar com `Violation of PRIMARY KEY constraint`, e a mensagem cita a data.
- Um dia cadastrado deixa de contar como tempo **comercial** (P3, P4 e P5). P1 e P2 contam corrido e não mudam.
- Os valores só mudam depois de **atualizar**. Como o cálculo usa a vida inteira de cada chamado, uma data nova pode alterar chamados de ciclos já carregados.
- Incluir uma data nova **muda resultado**. Na A2B, isso exige validação antes de ir para o painel.
