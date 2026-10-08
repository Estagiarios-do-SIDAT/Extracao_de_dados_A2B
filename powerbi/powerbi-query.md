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
**HTML Content**: `powerbi/documentacao-powerbi-a2b.html`. Ela deriva deste
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
3. Confira `SharePointFeriadosLink`, no topo do `.m`: o link do `feriados.txt` oficial no SharePoint, já preenchido (ver [seção 14](#14-feriados-e-sharepoint)).
4. Credenciais: SQL Server como hoje; SharePoint com **conta organizacional**. Privacidade das duas fontes: **Organizacional**. No gateway, permitir fontes de nuvem.
5. Carregue e, na primeira vez, confira a quantidade de chamados (ver [seção 11](#11-conferência)).
6. Nas próximas vezes, basta **Atualizar**: o período se ajusta sozinho (ver [seção 5](#5-período-da-consulta)) e o arquivo de feriados é lido de novo.
7. Na primeira atualização depois de qualquer mudança no texto SQL, o Power BI pede para **aprovar a execução da consulta nativa**. Isso é esperado.

Não é preciso ajustar datas a cada mês. Arquivo de feriados não encontrado na pasta configurada, sem acesso ou com linha inválida **falham a atualização** com mensagem; o painel nunca é calculado sem feriados. Requisitos do serviço e checklist do primeiro refresh na [seção 14](#14-feriados-e-sharepoint).

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
3. Gere uma cópia com os feriados declarados (`.\tools\executar_consulta.ps1 -Consulta .\queries\consulta_faia_farc_painel.sql -GerarSql C:\temp\painel.sql`), abra-a **inteira** e execute **sem selecionar trecho**. Executar só um pedaço quebra a consulta: as tabelas temporárias dos blocos anteriores não existiriam. O arquivo original, sem `@Feriados`, falha com `Must declare the scalar variable "@Feriados"`.
4. Use as **mesmas credenciais ou permissões equivalentes** às do Power BI — basta leitura nas tabelas acima e permissão de criar tabela temporária em `tempdb`.
5. Não é preciso sessão limpa. As 45 tabelas temporárias têm nomes exclusivos e cada bloco começa com `IF OBJECT_ID(...) DROP TABLE`, então a consulta roda duas vezes seguidas na mesma sessão e também depois das consultas individuais da Protect4 e da Decision.

### Se der erro no SSMS

| Erro | Causa provável | O que fazer |
|---|---|---|
| `Msg 208 — Invalid object name 'dbo.call_req'` | Sessão em outro banco | Selecionar `mdb`; conferir se o `USE mdb;` do topo foi colado junto |
| `Msg 207 — Invalid column name` | Tabela temporária antiga, de outra versão do script, ainda viva na sessão | Abrir sessão nova e repetir; se persistir, é defeito do arquivo e deve ser investigado |
| `Msg 1088 / objeto #... não existe` | Foi executado só um trecho selecionado | Executar o arquivo inteiro |
| `Must declare the scalar variable "@Feriados"` | Arquivo executado sem a lista de feriados | Gerar a cópia com `tools/executar_consulta.ps1 -GerarSql` |
| `Feriados: @Feriados vazio ou invalido` / `data fora do formato` | Lista de feriados vazia ou com data inválida | Corrigir o `feriados.txt` ([seção 14](#14-feriados-e-sharepoint)) |
| Nada retorna / demora demais | Volume ou bloqueio | Aguardar; comparar com o tempo de atualização no Power BI |

Ao relatar um problema, informe sempre: **cliente** (Power BI ou SSMS), **banco atual**, **usuário**, **mensagem de erro completa com o número da linha** e se o arquivo foi executado inteiro.

---

## 5. Período da consulta

O período é **automático**. Não há data para editar a cada mês. **Esta seção vale para a consulta do Power BI** (`powerbi/consulta_faia_farc_power_bi.m`, que executa `queries/consulta_faia_farc_painel.sql`); as consultas individuais têm período próprio, digitado no arquivo — ver [seção 2](#2-consultas-de-referência).

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

A lista de datas que **não** são dias úteis fica no **calendário** `feriados.txt`, e não no SQL: no SharePoint para o painel, lido a cada atualização, e em `docs/feriados.txt` para as consultas individuais. É o calendário do TCU, o mesmo para Virtual TI, Decision e A2B (não há lista por projeto). Formato do arquivo, cadastro de um ano novo, falhas e SharePoint na [seção 14](#14-feriados-e-sharepoint). A lista é usada só no **calendário comercial** (P3, P4 e P5). Chamados **P1 e P2 contam corrido** e ignoram essa lista por completo.

O bloco `[S.2]` do SQL recebe a lista no parâmetro `@Feriados`, valida e monta **duas** tabelas, e o FAIA e o FARC usam **as mesmas duas** — não existe um calendário para cada indicador:

| Estrutura | O que guarda | Data no arquivo (seção) |
|---|---|---|
| `#PBI_FeriadosFixos` | Feriados que caem sempre no mesmo dia, todo ano | `DD-MM` em `## Feriados Fixos` — ex.: `25-12` |
| `#PBI_FeriadosPorData` | Feriado nacional de data variável (Paixão de Cristo) e pontos facultativos do TCU | `DD-MM-AAAA` em `## Feriados móveis/diferenciados` ou `## Pontos Facultativos` — ex.: `05-06-2026` |

A diferença é só essa: o que se repete todo ano entra **uma vez** como `DD-MM` e vale para sempre; o que muda de data a cada ano (Carnaval, Paixão de Cristo, emendas) entra como `DD-MM-AAAA`, **ano a ano**. O script e o `.m` convertem para o formato do SQL (`MM-DD`, `AAAA-MM-DD`) antes de enviar `@Feriados`.

O que entra em cada lista:

- **feriados nacionais fixos** — Confraternização Universal, Tiradentes, Dia do Trabalho, Independência, Nossa Senhora Aparecida, Finados, Proclamação da República, Consciência Negra e Natal;
- **feriado nacional de data variável** (`## Feriados móveis/diferenciados`) — Paixão de Cristo;
- **pontos facultativos do TCU** (`## Pontos Facultativos`) — Carnaval, Quarta-Feira de Cinzas, Corpus Christi, emendas de feriado, véspera de Natal e de Ano-Novo, Dia do Servidor Público e datas extraordinárias.

A seção segue a classificação da Portaria do TCU (feriado nacional ou ponto facultativo), e não o fato de a data mudar a cada ano: Carnaval e Corpus Christi também mudam de data, mas a Portaria os define como ponto facultativo. As duas seções têm o mesmo efeito no cálculo. A Páscoa cai sempre num domingo e não precisa de cadastro.

**Sábados e domingos não devem ser cadastrados.** A consulta já os descarta sozinha, pelo dia da semana. Cadastrar um fim de semana não muda o resultado, só polui a lista.

**Fonte das datas.** Só fonte **oficial do TCU**: a portaria anual do Presidente do TCU que "divulga os feriados nacionais e define os dias de ponto facultativo" do ano, publicada no Boletim do TCU, **e todas as portarias que a alterarem**. Consulte em `pesquisa.apps.tcu.gov.br`, base **Normas**: a ficha da portaria anual lista, em "Alterada por", as alterações. Não use calendário civil genérico nem de outro órgão.

### Como atualizar

1. Abra o `feriados.txt` no SharePoint.
2. Acrescente a data, sozinha na linha, na seção certa (`## Feriados móveis/diferenciados` ou `## Pontos Facultativos`). Registre a Portaria (número e código de autenticidade) no histórico do projeto (`project-context/`). Ex.: `05-06-2026` em `## Pontos Facultativos` (Portaria-TCU nº 1/2026). Feriados nacionais fixos (`DD-MM`) já valem todo ano e não se repetem.
3. Não inclua sábados e domingos — já são tratados automaticamente.
4. Salve. A próxima atualização do painel já usa a lista nova: não é preciso mudar o SQL nem republicar o relatório.
5. Copie o mesmo arquivo para o `docs/feriados.txt` dos repositórios Virtual TI, Decision e A2B e para `Documentos e Relatórios/feriados.txt`, e rode `tools/verificar_feriados.ps1`; as consultas individuais passam a usar a lista nova.
6. Valide um chamado P3/P4/P5 que atravesse a nova data.

Data inválida, repetida, fora do formato ou fora da seção certa, ou arquivo inacessível, **falham a atualização** com mensagem.

> **Manutenção anual.** Os feriados fixos já estão prontos e não precisam de nada. O que precisa de atenção **todo ano** são as datas únicas: os feriados móveis e os pontos facultativos do TCU de cada ano coberto pela janela.

**Situação atual do cadastro.** Calendário do TCU de **2025 e 2026 completos**, conferido no Boletim do TCU pelos códigos de autenticidade (lista no histórico do projeto, `project-context/`):

| Ano | Portaria anual | Alterações | Datas por ano no arquivo |
|---|---|---|---|
| 2025 | Portaria-TCU nº 10, de 13/01/2025 | nº 67, nº 157 e nº 176 de 2025 | 03/03, 04/03, 05/03, 17/04, 18/04, 02/05, 19/06, 20/06, 27/10, 21/11, 24/12, 26/12, 31/12 |
| 2026 | Portaria-TCU nº 1, de 08/01/2026 (02/01 também pela nº 179/2025) | nº 93 de 2026 | 02/01, 16–18/02, 02/04, 03/04, 20/04, 04/06, 05/06, 29/06, 28/10, 24/12, 31/12 |

O PDF da portaria de 2026 guardado em `Documentos e Relatórios` é a versão **original**: a data de 29/06/2026 veio depois, pela Portaria nº 93/2026, e não aparece nele. Até 2026-10-06 a A2B só tinha as datas de 2025 a partir de 27/10 e tinha 05/04/2026 (Páscoa, domingo), que não está na Portaria; desde 2026-10-07 usa o calendário completo, igual ao da Virtual TI e da Decision.

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
- o `.m` foi validado com o motor do Power BI Desktop, fora do PBIX e com o arquivo de feriados servido localmente: executa com as duas fontes como Organizacional e o firewall de privacidade ativo, e devolve o mesmo resultado do SQL. A primeira versão gerada (um passo por etapa) era recusada pelo firewall (*Formula.Firewall*); a atual faz tudo num único passo (`Fonte`). O acesso ao SharePoint Online real (OAuth2), o gateway e o refresh no serviço ainda dependem de validação no PBIX ([seção 14](#14-feriados-e-sharepoint)).
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

O caminho recomendado é alterar `queries/consulta_faia_farc_painel.sql` no repositório, gerar o `.m` de novo (`.\tools\gerar_powerbi_m.ps1 -Consulta .\queries\consulta_faia_farc_painel.sql -Saida .\powerbi\consulta_faia_farc_power_bi.m`) e colar o `.m` inteiro no Editor Avançado. O `.m` gerado é versionado no repositório.

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
2. Abra o `feriados.txt` no SharePoint.
3. **Adicionar:** inclua a data (`DD-MM-AAAA`) na seção certa e registre a Portaria no histórico do projeto (`project-context/`). Feriados nacionais fixos (`DD-MM`) já valem todo ano.
4. **Corrigir:** edite a data na linha existente.
5. **Remover:** apague a linha da data.
6. Salve. A próxima atualização do painel já usa a lista nova.
7. Copie o mesmo arquivo para o `docs/feriados.txt` dos repositórios Virtual TI, Decision e A2B e para `Documentos e Relatórios/feriados.txt`, e rode `tools/verificar_feriados.ps1`; as consultas individuais passam a usar a lista nova.

**Cuidados.**

- Data inválida, repetida, fora do formato, fora da seção certa, seção desconhecida ou arquivo inacessível **falham a atualização** com a linha do problema.
- Um dia cadastrado deixa de contar como tempo **comercial** (P3, P4 e P5). P1 e P2 contam corrido e não mudam.
- Os valores só mudam depois de **atualizar**. Como o cálculo usa a vida inteira de cada chamado, uma data nova pode alterar chamados de ciclos já carregados.
- Incluir uma data nova **muda resultado**. Na A2B, isso exige validação antes de ir para o painel.

## 14. Feriados e SharePoint

O calendário de feriados e pontos facultativos do TCU fica no arquivo
`feriados.txt`, e não no SQL. É o mesmo para Virtual TI, Decision e A2B. Esta
seção é a referência completa do arquivo e da leitura pelo Power BI; o próprio
arquivo traz só um resumo de cinco linhas, para que as datas fiquem logo no
início.

### Para que serve

- **Horário TCU:** conta de segunda a sexta, das 08:00 às 20:00. Cada data do
  calendário sai **inteira** do Horário TCU (não existe meio expediente).
  Sábado e domingo já ficam de fora sem cadastro; por isso a Páscoa, que é
  sempre num domingo, não aparece no arquivo.
- **24x7:** soma todas as horas, inclusive fins de semana, feriados e pontos
  facultativos. O calendário não altera a contagem 24x7.
- **Fonte das datas:** só a Portaria do TCU que "divulga os feriados nacionais e
  define os dias de ponto facultativo" do ano, publicada no Boletim do TCU, e
  todas as Portarias que a alterarem (`pesquisa.apps.tcu.gov.br`, base
  **Normas**; a ficha da Portaria anual lista as alterações em "Alterada por").
  Não entram feriados estaduais, municipais ou de outros órgãos.

### As três seções

| Seção (título literal no arquivo) | O que guarda | Formato | Vale |
|---|---|---|---|
| `## Feriados Fixos` | feriados nacionais que caem sempre no mesmo dia | `DD-MM` | todo ano |
| `## Feriados móveis/diferenciados` | datas que a Portaria classifica como **feriado nacional**, mas cujo dia muda a cada ano (hoje, só a Paixão de Cristo) | `DD-MM-AAAA` | só naquele dia |
| `## Pontos Facultativos` | dias que a Portaria define como **ponto facultativo**: Carnaval, Quarta-Feira de Cinzas, Corpus Christi, emendas, vésperas, Dia do Servidor Público e datas extraordinárias | `DD-MM-AAAA` | só naquele dia |

A seção segue a **classificação da Portaria**, e não o fato de a data mudar de
um ano para outro: Carnaval e Corpus Christi também mudam de data, mas a
Portaria-TCU nº 1/2026, por exemplo, os define como ponto facultativo e a
Paixão de Cristo como feriado nacional. As duas seções com ano têm o mesmo
efeito no cálculo; a separação serve para conferir o arquivo contra a
Portaria.

### Formato do arquivo (contrato de leitura)

O `.m` do Power BI e o `tools/feriados.ps1` (usado pelo
`verificar_feriados.ps1` e pelo `executar_consulta.ps1`) aplicam as mesmas
regras e dão o mesmo resultado para o mesmo arquivo. Cada linha, sem os espaços
das pontas, é classificada assim:

| Linha (exemplo) | Como é lida |
|---|---|
| `## Pontos Facultativos` | título de uma das três seções; maiúsculas, acentos e espaços a mais no nome não importam |
| `## Observações`, `### Notas` | qualquer linha que comece com `##` é título: se o nome não for uma das três seções, **erro** |
| `25-12` | feriado fixo, só em `## Feriados Fixos`; vale para o mesmo dia e mês de todos os anos |
| `04-06-2026` | data com ano, só em `## Feriados móveis/diferenciados` ou `## Pontos Facultativos`; vale só nesse dia |
| `Ano de 2026.`, linha vazia, frase de texto | ignorada |
| `04-06-2026 Corpus Christi` | **ignorada sem erro**: a data fica fora do calendário sem aviso |
| `2026.`, `04/06/2026`, `4-6-2026`, `2026-06-04` | só números e sinais, fora do formato: **erro** |
| `31-04-2026`; data repetida, mesmo em outra seção; data na seção errada | **erro** |

Por isso:

- **escreva cada data sozinha na linha**; um comentário vai na linha de cima;
- **o rótulo de ano começa com a palavra "Ano"** (`Ano de 2027.`). A linha
  `2027.` sozinha interrompe a atualização;
- não renomeie, traduza nem crie títulos de seção;
- salve em **UTF-8** (com ou sem BOM). UTF-16, ou ANSI (Windows-1252) com
  acentos, são rejeitados. Quebras de linha CRLF ou LF funcionam igual;
- o arquivo precisa ter pelo menos uma data;
- um feriado fixo em `29-02` só valeria nos anos bissextos.

Um ano sem nenhuma data com ano cadastrada **não** dá erro: nesse ano só os
feriados fixos saem do Horário TCU, e a Paixão de Cristo e os pontos
facultativos contam como dias úteis. Por isso o ano novo precisa ser cadastrado
assim que a Portaria for publicada.

### Onde ficam as cópias

| Cópia | Quem usa |
|---|---|
| SharePoint, site `EstgioSidatTCU`, biblioteca *Documentos Compartilhados*, pasta `Atividades Avulsas/Indicadores e Relatórios de Serviços/Documentos e Relatórios/` | **o Power BI** (os três relatórios) |
| `docs/feriados.txt` dos repositórios Virtual TI, Decision e A2B | consultas executadas pelo repositório (`tools/executar_consulta.ps1`) e o verificador |
| `Documentos e Relatórios/feriados.txt` (pasta de trabalho, fora do Git) | referência; conferida pelo verificador |

As cópias do repositório e a de `Documentos e Relatórios` devem ser idênticas;
o `tools/verificar_feriados.ps1` confere. **Publicar no GitHub não atualiza o
SharePoint**, e editar no SharePoint não atualiza o repositório: as duas pontas
são atualizadas à mão. O mesmo site também guarda cópias sincronizadas dos
repositórios (`Repositórios/Extracao_de_dados_*/docs/feriados.txt`); o Power BI
não as lê, porque a consulta exige a pasta do link.

### Cadastrar um ano novo ou alterar datas

1. Confirme as datas na Portaria do ano (e nas que a alterarem).
2. Edite o `docs/feriados.txt` de um dos repositórios:
   - **Feriados Fixos:** nada a fazer; já valem para o ano novo (só muda se a
     Portaria criar um feriado nacional fixo novo);
   - nas outras duas seções, acrescente `Ano de AAAA.` e, abaixo, as datas do
     ano, cada uma na seção que a Portaria indicar;
   - Portaria que altere o calendário durante o ano: incluir, corrigir ou
     apagar a data;
   - não cadastre ano futuro antes da Portaria; não apague anos anteriores
     (chamados antigos continuam sendo calculados com eles).
3. Copie o arquivo para o `docs/feriados.txt` dos outros dois repositórios e
   para `Documentos e Relatórios/feriados.txt`.
4. Valide em qualquer um dos repositórios: `.\tools\verificar_feriados.ps1`.
   Ele lê o arquivo com as regras acima, mostra quantas datas há por seção e
   por ano, compara as cópias e confere se o `.m` está em dia.
5. **Substitua o `feriados.txt` na pasta do SharePoint** (mesmo nome, mesma
   pasta) pelo arquivo validado.
6. Atualize o relatório no Power BI. Não é preciso mudar o SQL, gerar o `.m` de
   novo nem republicar o relatório.
7. Registre a Portaria (número e código de autenticidade) no histórico do
   projeto (`project-context/`).

### Como o Power BI lê o calendário

O cálculo do Horário TCU é feito no SQL Server, que não lê o SharePoint. A
consulta do Power BI (`.m`) faz a leitura e entrega a lista ao SQL. A **única
configuração** fica no topo do `.m`, logo abaixo de `let`: o link do
`feriados.txt` copiado do SharePoint (*Copiar link*, ou o endereço com o
arquivo aberto).

```powerquery
SharePointFeriadosLink = "https://tcucloud.sharepoint.com/:t:/r/sites/EstgioSidatTCU/Documentos%20Compartilhados/Atividades%20Avulsas/Indicadores%20e%20Relat%C3%B3rios%20de%20Servi%C3%A7os/Documentos%20e%20Relat%C3%B3rios/feriados.txt?d=w3744a75ddc284a38890b5d9c4af44be3&csf=1&web=1&e=hwfUQM",
```

1. **O link não é aberto.** Ele serve só para identificar o arquivo: o `.m`
   separa o caminho com `Uri.Parts` (o que vem depois de `?` é descartado),
   tira o prefixo de compartilhamento `/:t:/r`, decodifica os `%XX`
   (`%20` → espaço, `%C3%B3` → `ó`...) e obtém a pasta e o nome:

   | Extraído do link | Valor |
   |---|---|
   | Site | `https://tcucloud.sharepoint.com/sites/EstgioSidatTCU` |
   | Pasta | `https://tcucloud.sharepoint.com/sites/EstgioSidatTCU/Documentos Compartilhados/Atividades Avulsas/Indicadores e Relatórios de Serviços/Documentos e Relatórios/` |
   | Nome | `feriados.txt` |

2. **A leitura é feita por `SharePoint.Files`, num site fixo:**

   ```powerquery
   ArquivosSite = SharePoint.Files("https://tcucloud.sharepoint.com/sites/EstgioSidatTCU", [ApiVersion = 15]),
   ```

   O endereço é **literal** (vem do gerador, `tools/gerar_powerbi_m.ps1`), e
   não montado a partir do link: o Power BI Service só agenda a atualização
   de fontes que ele reconhece sem executar a consulta. A credencial é a
   **Conta organizacional**. Um link de outro site, ou de outro domínio, é
   erro; para usar outro site, altere `$SiteConexao` no gerador e gere os `.m`
   de novo.
3. Ficam só os arquivos com o **nome e a pasta** do link (coluna
   `[Folder Path]`; sem diferença de maiúsculas e da barra final). O site tem
   outras cópias com o mesmo nome (dentro de
   `Repositórios/Extracao_de_dados_*/docs/`); por isso a pasta é obrigatória.
   Deve sobrar **exatamente um** arquivo. Nenhum: a atualização falha com a
   lista das pastas do site que têm um arquivo com esse nome. Mais de um: a
   atualização falha. Nunca se escolhe a primeira linha.
4. O conteúdo (`[Content]`) é lido como UTF-8 e validado linha a linha com as
   regras da tabela acima. Qualquer erro, ou nenhuma data, faz a etapa `Fonte`
   falhar com `Feriados: ...` e o número da linha; o SQL nem é executado.
5. A lista vai ao SQL no **parâmetro** `@Feriados`, em JSON (`DD-MM` → `MM-DD`,
   `DD-MM-AAAA` → `AAAA-MM-DD`), por `Value.NativeQuery`. Nada do link nem do
   arquivo é concatenado no SQL. O SQL confere o formato de novo e monta duas
   listas: os dias e meses que valem todo ano e as datas que valem uma vez.

**Quando mexer no link:** só se o `feriados.txt` mudar de pasta ou de nome
(cole o link novo, do mesmo site). Trocar as datas dentro do mesmo arquivo não
exige mudar o Power Query.

**Links que não servem:** o link curto de compartilhamento
(`https://tcucloud.sharepoint.com/:t:/s/<site>/<identificador>`) não traz o
caminho do arquivo, e a consulta recusa (não se adivinha a pasta). O link
nunca é aberto com `Web.Contents`: com ele, o Power BI Desktop recusou a
credencial organizacional.

### Configurar no Power BI Desktop

1. Abra a consulta do relatório no Editor do Power Query e clique em
   *Editor Avançado* (ou, para uma consulta nova: *Página Inicial → Nova
   Fonte → Consulta Nula → Editor Avançado*). Substitua todo o texto pelo
   `.m` inteiro. O `.m` não vai no campo *Instrução SQL*.
2. Confira a linha `SharePointFeriadosLink`: deve ser o link do `feriados.txt`
   oficial (pasta `Documentos e Relatórios`).
3. Credenciais (*Arquivo → Opções e configurações → Configurações da fonte de
   dados*):
   - SharePoint (`https://tcucloud.sharepoint.com/sites/EstgioSidatTCU`, ou a
     raiz do tenant): **Conta organizacional → Entrar**, com o usuário do TCU;
   - SQL Server (`bdados-14r`, `mdb`): a mesma credencial de hoje.
4. Privacidade das duas fontes: **Organizacional** (*Editar permissões* em
   cada uma). Não desative os níveis de privacidade.
5. *Atualizar visualização*. Na primeira vez (e a cada mudança do SQL),
   aprovar a execução da consulta nativa.
6. A consulta só carrega se encontrou exatamente um `feriados.txt` na pasta do
   link e se o arquivo é válido. Se aparecer `Feriados: ...`, a mensagem diz o
   motivo (link, pasta, linha do arquivo).

**Formula.Firewall:** a leitura do SharePoint e o SQL ficam num único passo
(`Fonte`); não separe os passos. `SharePointFeriadosLink` é só texto e pode
ficar no topo.

### Publicar e agendar no Power BI Service

Roteiro para a equipe que publica os relatórios. **Esta configuração ainda não
foi validada no serviço**; só uma atualização real bem-sucedida confirma.

1. **Publicar:** no Power BI Desktop, com a consulta já atualizada sem erro,
   *Página Inicial → Publicar* no workspace do relatório (substituindo o
   conjunto de dados existente).
2. **SharePoint Online:** no serviço, *conjunto de dados (modelo semântico) →
   Configurações → Credenciais da fonte de dados* → fonte SharePoint
   (`https://tcucloud.sharepoint.com/sites/EstgioSidatTCU`) → *Editar
   credenciais*: método **OAuth2**, nível de privacidade **Organizacional**,
   entrar com a conta institucional. A credencial é de quem a configura: se
   essa conta perder o acesso ao site, a atualização falha.
3. **SQL Server:** mantém a configuração atual (`bdados-14r`, `mdb`), pelo
   gateway de dados local, com a mesma credencial e privacidade
   **Organizacional**.
4. **Gateway e nuvem:** a consulta combina o SharePoint (nuvem) e o SQL Server
   (local) num único passo, então ela é avaliada pelo gateway. Em
   *Gerenciar conexões e gateways*, no cluster do gateway, habilitar
   *Permitir que as fontes de dados de nuvem do usuário sejam atualizadas por
   este cluster de gateway*; nas configurações do conjunto de dados, mapear o
   SQL Server para a conexão do gateway e o SharePoint para a conexão de nuvem
   (OAuth2), conforme o ambiente oferecer.
5. **Teste manual:** *Atualizar agora* e conferir o *Histórico de atualização*
   (status *Concluído*). Conferir no relatório o número de chamados.
6. **Atualização agendada:** configurar o agendamento e, depois da primeira
   execução agendada, conferir de novo o histórico.
7. **Erros comuns:**
   - *contém uma fonte de dados dinâmica* / *não é possível atualizar*: alguém
     trocou o endereço literal de `SharePoint.Files` ou de `Sql.Database` por
     um valor calculado; gere o `.m` de novo pelo gerador;
   - *credenciais inválidas / expiradas* na fonte SharePoint: refazer o login
     OAuth2 (passo 2);
   - *Formula.Firewall*: os passos da consulta foram separados; cole o `.m`
     inteiro de novo;
   - `Feriados: ...`: problema no link ou no conteúdo do arquivo (a mensagem
     indica qual).

### Falhas que interrompem a atualização

Com a mensagem e, quando for o caso, a linha do arquivo:

- credencial do SharePoint ausente ou sem acesso ao site;
- `SharePointFeriadosLink` inválido, de outro site ou sem o caminho do arquivo
  (link curto `/:t:/s/...`);
- arquivo não encontrado na pasta do link, ou mais de um arquivo nela;
- arquivo vazio, sem nenhuma data ou fora de UTF-8;
- título de seção desconhecido;
- data fora do formato, inexistente, repetida ou na seção errada;
- linha só com números e sinais que não seja uma data válida.

O relatório nunca é calculado com zero feriados. Atenção: uma data com texto na
mesma linha **não** interrompe a atualização; ela é ignorada (ver o formato,
acima).

### Onde o calendário pesa neste projeto

P3, P4 e P5 contam no Horário TCU (no SQL, `COMERCIAL`) e perdem os dias cadastrados; P1 e P2 contam 24x7 (no SQL, `CORRIDA`) e não mudam. Os dois indicadores (FAIA e FARC) usam o mesmo calendário. Lista por tipo de data e situação do cadastro na [seção 10](#10-feriados-e-pontos-facultativos).
