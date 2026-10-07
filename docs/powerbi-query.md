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

O SQL não é mais colado em **Instrução SQL**: os feriados vêm de um arquivo no SharePoint, que o SQL Server não lê. A consulta do painel é `powerbi/consulta_faia_farc_power_bi.m` (Power Query M), gerada a partir do `.sql` por `tools/gerar_powerbi_m.ps1`. Ela lê o arquivo de feriados, valida e executa o `.sql` com o parâmetro `@Feriados`.

1. **Página Inicial → Nova Fonte → Consulta Nula → Editor Avançado.**
2. Cole o conteúdo inteiro de `consulta_faia_farc_power_bi.m`.
3. Troque `INSERIR_URL_DO_ARQUIVO_FERIADOS_NO_SHAREPOINT` pelo link direto do `feriados.csv` no SharePoint (o mesmo da Virtual e da Decision).
4. Credenciais: SQL Server como hoje; SharePoint com **conta organizacional**. Privacidade das duas fontes: **Organizacional**. No gateway, permitir fontes de nuvem.
5. Carregue e, na primeira vez, confira a quantidade de chamados (ver [seção 11](#11-conferência)).
6. Nas próximas vezes, basta **Atualizar**: o período se ajusta sozinho (ver [seção 5](#5-período-da-consulta)) e o arquivo de feriados é lido de novo.
7. Na primeira atualização depois de qualquer mudança no texto SQL, o Power BI pede para **aprovar a execução da consulta nativa**. Isso é esperado.

Não é preciso ajustar datas a cada mês. Arquivo de feriados inacessível, placeholder não preenchido ou linha inválida **falham a atualização** com mensagem; o painel nunca é calculado sem feriados. Requisitos do serviço e checklist do primeiro refresh em [feriados.md](feriados.md).

---

## 4. Power BI e SQL Server

### Quem executa a consulta

O `.sql` é **T-SQL puro**. O `.m` só lê e valida o arquivo de feriados e envia o SQL por `Value.NativeQuery`, com o parâmetro `@Feriados`.

```text
A consulta é usada pelo Power BI, mas é executada pelo SQL Server.
O Power BI envia o script pelo conector, com o parâmetro @Feriados, e importa o resultado.
```

Ou seja: o Power BI **não calcula nada**. Ele abre a conexão, manda o texto do script e a lista de feriados, espera e recebe o result set final. Quem compila, otimiza e executa é o SQL Server.

A consequência é direta: **em condições equivalentes, o mesmo script deve rodar integralmente no SSMS**, com `@Feriados` declarado. Se ele funciona no Power BI e não no SSMS, isso não é uma característica do Power BI — é uma diferença de **contexto de execução**, e ela precisa ser identificada.

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
3. Gere uma cópia com os feriados declarados (`.\tools\executar_consulta.ps1 -Consulta .\powerbi\consulta_faia_farc_power_bi.sql -GerarSql C:\temp\painel.sql`), abra-a **inteira** e execute **sem selecionar trecho**. Executar só um pedaço quebra a consulta: as tabelas temporárias dos blocos anteriores não existiriam. O arquivo original, sem `@Feriados`, falha com `Must declare the scalar variable "@Feriados"`.
4. Use as **mesmas credenciais ou permissões equivalentes** às do Power BI — basta leitura nas tabelas acima e permissão de criar tabela temporária em `tempdb`.
5. Não é preciso sessão limpa. As 45 tabelas temporárias têm nomes exclusivos e cada bloco começa com `IF OBJECT_ID(...) DROP TABLE`, então a consulta roda duas vezes seguidas na mesma sessão e também depois das consultas individuais da Protect4 e da Decision.

### Se der erro no SSMS

| Erro | Causa provável | O que fazer |
|---|---|---|
| `Msg 208 — Invalid object name 'dbo.call_req'` | Sessão em outro banco | Selecionar `mdb`; conferir se o `USE mdb;` do topo foi colado junto |
| `Msg 207 — Invalid column name` | Tabela temporária antiga, de outra versão do script, ainda viva na sessão | Abrir sessão nova e repetir; se persistir, é defeito do arquivo e deve ser investigado |
| `Msg 1088 / objeto #... não existe` | Foi executado só um trecho selecionado | Executar o arquivo inteiro |
| `Must declare the scalar variable "@Feriados"` | Arquivo executado sem a lista de feriados | Gerar a cópia com `tools/executar_consulta.ps1 -GerarSql` |
| `Feriados: @Feriados vazio ou invalido` / `data fora do formato` | Lista de feriados vazia ou com data inválida | Corrigir o arquivo de feriados ([feriados.md](feriados.md)) |
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
- No comercial, **feriados e pontos facultativos do TCU não contam**. Eles vêm do arquivo de feriados (seção 10), em duas formas: feriados fixos (que se repetem todo ano) e feriados móveis/pontos facultativos (por data).

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

A lista de datas que **não** são dias úteis fica no **arquivo de feriados** (`feriados.csv`), e não no SQL: no SharePoint para o painel, lido a cada atualização, e em `config/feriados.csv` para as consultas individuais. É o calendário do TCU, o mesmo para Virtual, Decision e A2B (não há lista por projeto). Formato, validação e falhas em [feriados.md](feriados.md). A lista é usada só no **calendário comercial** (P3, P4 e P5). Chamados **P1 e P2 contam corrido** e ignoram essa lista por completo.

O bloco `[S.2]` do SQL recebe a lista no parâmetro `@Feriados`, valida e monta **duas** tabelas, e o FAIA e o FARC usam **as mesmas duas** — não existe um calendário para cada indicador:

| Estrutura | O que guarda | `Data` no arquivo |
|---|---|---|
| `#PBI_FeriadosFixos` | Feriados que caem sempre no mesmo dia, todo ano | `MM-DD` — ex.: `12-25` |
| `#PBI_FeriadosPorData` | Feriados móveis e pontos facultativos do TCU | `AAAA-MM-DD` — ex.: `2026-06-05` |

A diferença é só essa: o que se repete todo ano entra **uma vez** como `MM-DD` e vale para sempre; o que muda de data a cada ano (Carnaval, Páscoa, emendas) entra como `AAAA-MM-DD`, **ano a ano**.

O que entra em cada lista:

- **feriados nacionais fixos** — Confraternização Universal, Tiradentes, Dia do Trabalho, Independência, Nossa Senhora Aparecida, Finados, Proclamação da República, Consciência Negra e Natal;
- **feriados móveis** — Carnaval, Paixão de Cristo, Páscoa, Corpus Christi;
- **pontos facultativos do TCU** — emendas de feriado, véspera de Natal e de Ano-Novo, e os dias de Carnaval e Quarta-Feira de Cinzas.

**Sábados e domingos não devem ser cadastrados.** A consulta já os descarta sozinha, pelo dia da semana. Cadastrar um fim de semana não muda o resultado, só polui a lista.

**Fonte das datas.** Só fonte **oficial do TCU**: a portaria anual do Presidente do TCU que "divulga os feriados nacionais e define os dias de ponto facultativo" do ano, publicada no Boletim do TCU, **e todas as portarias que a alterarem**. Consulte em `pesquisa.apps.tcu.gov.br`, base **Normas**: a ficha da portaria anual lista, em "Alterada por", as alterações. Não use calendário civil genérico nem de outro órgão.

### Como atualizar

1. Abra o `feriados.csv` no SharePoint.
2. Acrescente uma linha por data, no formato `Data,Descricao,Fonte`, com a Portaria na coluna `Fonte`. Ex.: `2026-06-05,Ponto facultativo - emenda após Corpus Christi,Portaria-TCU nº 1/2026`. Feriados nacionais fixos (`MM-DD`) já valem todo ano e não se repetem.
3. Não inclua sábados e domingos — já são tratados automaticamente.
4. Salve. A próxima atualização do painel já usa a lista nova: não é preciso mudar o SQL nem republicar o relatório.
5. Copie o mesmo conteúdo para o `config/feriados.csv` dos três repositórios (Virtual, Decision, A2B) e rode `tools/verificar_feriados.ps1`; as consultas individuais passam a usar a lista nova.
6. Valide um chamado P3/P4/P5 que atravesse a nova data.

Data inválida, coluna ausente ou arquivo inacessível **falham a atualização** com mensagem. Data repetida entra uma vez só.

> **Manutenção anual.** Os feriados fixos já estão prontos e não precisam de nada. O que precisa de atenção **todo ano** são as datas únicas: os feriados móveis e os pontos facultativos do TCU de cada ano coberto pela janela.

**Situação atual do cadastro.** Calendário do TCU de **2025 e 2026 completos**, conferido no Boletim do TCU pelos códigos de autenticidade ([feriados.md](feriados.md), seção 2):

| Ano | Portaria anual | Alterações | Datas por ano no arquivo |
|---|---|---|---|
| 2025 | Portaria-TCU nº 10, de 13/01/2025 | nº 67, nº 157 e nº 176 de 2025 | 03/03, 04/03, 05/03, 17/04, 18/04, 02/05, 19/06, 20/06, 27/10, 21/11, 24/12, 26/12, 31/12 |
| 2026 | Portaria-TCU nº 1, de 08/01/2026 (02/01 também pela nº 179/2025) | nº 93 de 2026 | 02/01, 16–18/02, 02/04, 03/04, 20/04, 04/06, 05/06, 29/06, 28/10, 24/12, 31/12 |

O PDF da portaria de 2026 guardado em `Documentos e Relatórios` é a versão **original**: a data de 29/06/2026 veio depois, pela Portaria nº 93/2026, e não aparece nele. Até 2026-10-06 a A2B só tinha as datas de 2025 a partir de 27/10 e tinha 05/04/2026 (Páscoa, domingo), que não está na Portaria; desde 2026-10-07 usa o calendário completo, igual ao da Virtual e da Decision.

As consultas individuais (`consulta_faia_a2b_protect4.sql` e `consulta_farc_a2b_protect4.sql`) leem a mesma lista da A2B, pelo mesmo parâmetro, e montam `#FeriadosFixos` e `#FeriadosPorData`. Não há mais lista própria em cada consulta.

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
- o `.m` foi validado com o motor do Power BI Desktop, fora do PBIX e com o arquivo de feriados servido localmente: executa com as duas fontes como Organizacional e o firewall de privacidade ativo, e devolve o mesmo resultado do SQL. A primeira versão gerada (um passo por etapa) era recusada pelo firewall (*Formula.Firewall*); a atual faz tudo num único passo (`Fonte`). O acesso ao SharePoint Online real (OAuth2), o gateway e o refresh no serviço ainda dependem de validação no PBIX ([feriados.md](feriados.md)).
- nas colunas compartilhadas `Data Abertura` e `Data Captura`, o painel usa o valor da metade FAIA, que difere do FARC individual em alguns chamados — 9 dos 234 do ciclo 24/03–23/04/2026. As colunas do FARC coincidem nos 234.
- a regra de arredondamento (proporcional, em vez de "hora ou fração") **ainda não foi confirmada contra o edital**. Se o edital exigir "hora ou fração", os quatro indicadores do projeto precisarão ser revistos.
- desde 2026-10-07 o painel e as duas consultas individuais leem a mesma lista de feriados da A2B. A diferença antiga do FAIA individual (sem `2025-12-24` e `2025-12-31`) acabou.

---

## 13. Manutenção no Power Query

O texto SQL fica dentro da consulta M, no valor `SqlTexto`. A quantidade de
ciclos é uma linha desse SQL. **Os feriados não ficam no SQL**: ficam no arquivo
de feriados no SharePoint.

### Onde fica o texto SQL

1. No Power BI Desktop: **Página Inicial → Transformar dados**. Abre o Power Query.
2. No painel **Consultas**, à esquerda, selecione a consulta da A2B.
3. **Página Inicial → Editor Avançado.** O SQL está no texto `SqlTexto`.
4. Depois de editar: **Concluído → Fechar e aplicar**. Na primeira atualização o Power BI pede para **aprovar a consulta nativa** — aprove.

O caminho recomendado é alterar `powerbi/consulta_faia_farc_power_bi.sql` no repositório, gerar o `.m` de novo (`.\tools\gerar_powerbi_m.ps1 -Consulta .\powerbi\consulta_faia_farc_power_bi.sql`) e colar o `.m` inteiro no Editor Avançado, trocando de novo o placeholder do SharePoint. O `.m` gerado é versionado no repositório.

### Mudar a quantidade de ciclos

A primeira instrução do SQL, logo no início de `SqlTexto`, é:

```sql
DECLARE @PBI_QuantidadeCiclos int = 12;
```

1. Abra o **Editor Avançado** como acima.
2. Troque `12` pelo número de ciclos — por exemplo `6` ou `18`.
3. **Concluído → Fechar e aplicar**, aprove a consulta nativa e atualize.

É o único número que muda. A regra do ciclo — do dia 24 até o final do dia 23
do mês seguinte — não depende dele.

A consulta usada pelo painel fica incorporada ao próprio relatório, então a
troca vale a partir da próxima atualização. Existe um repositório interno, usado
para versionamento e manutenção técnica, onde a mesma alteração é registrada
pela equipe responsável quando a cobertura muda em definitivo.

### Atualizar feriados

Sem mexer no SQL nem republicar o relatório:

1. Confirme a data na fonte oficial do TCU (seção 10).
2. Abra o `feriados.csv` no SharePoint.
3. **Adicionar:** inclua a linha (`AAAA-MM-DD`), com a Portaria na coluna `Fonte`. Feriados nacionais fixos (`MM-DD`) já valem todo ano.
4. **Corrigir:** edite a data, a descrição ou a fonte na linha existente.
5. **Remover:** apague a linha inteira.
6. Salve. A próxima atualização do painel já usa a lista nova.
7. Copie o mesmo conteúdo para o `config/feriados.csv` dos três repositórios e rode `tools/verificar_feriados.ps1`; as consultas individuais passam a usar a lista nova.

**Cuidados.**

- Data inválida, escopo desconhecido ou arquivo inacessível **falham a atualização** com a linha do problema. Data repetida entra uma vez só.
- Um dia cadastrado deixa de contar como tempo **comercial** (P3, P4 e P5). P1 e P2 contam corrido e não mudam.
- Os valores só mudam depois de **atualizar**. Como o cálculo usa a vida inteira de cada chamado, uma data nova pode alterar chamados de ciclos já carregados.
- Incluir uma data nova **muda resultado**. Na A2B, isso exige validação antes de ir para o painel.
