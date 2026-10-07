# Extração de dados — A2B / Protect4

Repositório com consultas SQL, documentações e planilhas de validação usadas para apurar os indicadores **FAIA** e **FARC** da **A2B / Protect4** a partir da base do **CA Service Desk Manager**.

O objetivo do projeto é manter, em um só lugar, as consultas usadas na apuração dos indicadores, a explicação das regras aplicadas e os arquivos de conferência contra os relatórios recebidos.

Este repositório atende **somente a A2B / Protect4**. COI e Decision têm repositórios próprios (`Extracao_de_dados_COI` e `Extracao_de_dados_Decision`) e nada deles vive aqui. A antiga pasta `Queries`, onde os três núcleos conviviam, **não é mais fonte operacional** — desde 2026-09-18 a fonte oficial da A2B é este repositório.

## Estrutura do repositório

```text
.
├── queries/
│   ├── consulta_faia_a2b_protect4.sql      referência técnica do FAIA
│   └── consulta_farc_a2b_protect4.sql      referência técnica do FARC
├── powerbi/
│   └── consulta_faia_farc_power_bi.sql     fonte do painel: FAIA e FARC, últimos 12 ciclos (24 → 23)
├── docs/
│   ├── faia-calculation.md                 como o FAIA é calculado
│   ├── farc-calculation.md                 como o FARC é calculado
│   ├── powerbi-query.md                    a consulta do painel: período, manutenção, colunas
│   └── documentacao-powerbi-a2b.html       leitura dentro do painel (visual HTML Content)
├── analysis/
│   └── planilhas de comparação
├── project-context/
│   └── A2B-HISTORICO-CONTEXTO-MESTRE.md    Histórico Mestre da A2B
├── support/
│   ├── consulta_logs_chamados_listados.sql
│   ├── consulta_status_chamados.sql
│   ├── consulta_status_hold.sql
│   └── consulta_tipos_chamado.sql
├── README.md
└── .git/
```

## O que é FAIA

O **FAIA** mede o prazo de **primeiro atendimento**.

A consulta identifica quando o chamado passou para o fornecedor e quando ocorreu o primeiro andamento do atendimento. Depois compara esse tempo com a meta definida para a severidade do chamado.

Quando o tempo passa da meta, a consulta calcula:

- tempo excedido;
- `nHR_FAIA`;
- valor final do FAIA.

## O que é FARC

O **FARC** mede o prazo de **atendimento/resolução**.

A consulta calcula o tempo considerado válido para o atendimento do chamado e compara esse total com a meta aplicável. Quando há extrapolação, calcula:

- tempo excedido;
- `nHR_FARC`;
- valor final do FARC.

## Consultas principais

A Protect4 tem dois grupos de arquivos, com finalidades diferentes.

**`queries/` — consultas individuais.** São as **referências técnicas** de cada indicador. É onde a regra de cálculo mora e é o que se consulta quando há dúvida sobre um número.

| Arquivo | Finalidade |
|---|---|
| `queries/consulta_faia_a2b_protect4.sql` | Calcula o FAIA da A2B/Protect4 |
| `queries/consulta_farc_a2b_protect4.sql` | Calcula o FARC da A2B/Protect4 |

**`powerbi/` — consulta consolidada do painel.** Reúne os dois indicadores para consumo pelo Power BI.

| Arquivo | Finalidade |
|---|---|
| `powerbi/consulta_faia_farc_power_bi.sql` | FAIA e FARC juntos, para o painel |

Ela:

- reúne FAIA e FARC do mesmo chamado na **mesma linha**;
- retorna **uma linha por chamado**;
- **não repete** as colunas compartilhadas do chamado;
- mantém as colunas específicas de cada indicador;
- foi estruturada para consumo pelo Power BI (um único resultado, sem `GO`, sem diagnósticos, tipos nativos);
- usa `nHR_FAIA` e `nHR_FARC` **proporcionais e decimais**;
- cobre automaticamente os **últimos 12 ciclos completos** (ciclo do dia 24 ao dia 23 do mês seguinte). A quantidade é `@PBI_QuantidadeCiclos`, a primeira instrução do SQL.

> A consulta consolidada **não substitui** as consultas individuais como referência técnica. Ela reaproveita os mesmos motores de cálculo; não reimplementa nenhuma regra.

**`docs/` — explicações.**

```text
docs/faia-calculation.md             como o FAIA é calculado
docs/farc-calculation.md             como o FARC é calculado
docs/powerbi-query.md                a consulta do painel: período, manutenção de ciclos e feriados, colunas
docs/feriados.md                     o arquivo de feriados (igual nos três repositórios)
docs/documentacao-powerbi-a2b.html   a mesma documentação do painel, para o visual HTML Content
```

**Feriados — `config/`, `tools/` e `powerbi/*.m`.** Os feriados e pontos
facultativos não ficam mais nos SQLs. Ficam no arquivo de feriados:
`config/feriados.csv` (cópia versionada, igual nos repositórios da Virtual, da
Decision e da A2B) e o mesmo arquivo no SharePoint, lido pelo painel a cada
atualização. Para incluir um feriado, basta editar o arquivo no SharePoint e
salvar: não se muda o SQL nem se republica o relatório.

```text
config/feriados.csv                  feriados e pontos facultativos (Data, Descricao, Escopo)
powerbi/consulta_faia_farc_power_bi.m consulta do painel (Power Query M): feriados do SharePoint + SQL
tools/executar_consulta.ps1          executa queries/ com os feriados do arquivo
tools/gerar_powerbi_m.ps1            gera powerbi/*.m a partir do .sql
tools/verificar_feriados.ps1         valida o arquivo e a sincronia dos repositórios
tools/feriados.ps1                   leitura e validação do arquivo (uso interno)
```

Detalhes em [`docs/feriados.md`](docs/feriados.md).

[Documentação da consulta consolidada do Power BI](docs/powerbi-query.md)

As planilhas em `analysis/` guardam as comparações usadas na validação dos resultados.

## Consultas de apoio

A pasta `support/` contém consultas auxiliares usadas durante análise e depuração.

| Arquivo | Uso |
|---|---|
| `support/consulta_logs_chamados_listados.sql` | Lista todos os logs dos chamados informados |
| `support/consulta_status_chamados.sql` | Lista os status cadastrados no SDM |
| `support/consulta_status_hold.sql` | Mostra cada status e o flag `cr_stat.hold`, que indica se ele para o relógio do SLA. O FARC não usa esse flag: os status que contam são uma lista explícita (ver [cálculo do FARC](docs/farc-calculation.md)) |
| `support/consulta_tipos_chamado.sql` | Lista os tipos de chamado e suas quantidades |

Essas consultas não calculam FAIA nem FARC. Elas servem para investigar chamados, conferir códigos e entender registros da base.

## Como usar as consultas

1. Abra o arquivo SQL do fornecedor e indicador desejado.
2. Ajuste o período de apuração nos parâmetros de data.
3. Mantenha `@MostrarDiagnostico = 0` para uso normal no relatório.
4. Execute pelo script, que lê os feriados de `config/feriados.csv` e grava o resultado em CSV: `.\tools\executar_consulta.ps1 -Consulta .\queries\<consulta>.sql -Saida C:\temp\a2b` (`-GerarSql` gera uma cópia para o SSMS). Aberto direto no SSMS, sem o script, o arquivo falha com *Must declare the scalar variable "@Feriados"*.
5. Exporte o resultado.
6. Compare com os arquivos recebidos do fornecedor.
7. Salve a análise na pasta `analysis/` correspondente.

Quando houver divergência, use `@MostrarDiagnostico = 1` para retornar tabelas intermediárias de conferência.

## Parâmetros comuns

**Consultas individuais** (`queries/`):

```sql
DECLARE @InicioBrasil datetime2(0) = '2026-03-24 00:00:00';  -- inclusivo
DECLARE @FimBrasil    datetime2(0) = '2026-04-23 23:59:59';  -- INCLUSIVO
DECLARE @MostrarDiagnostico bit = 0;
```

- `@InicioBrasil` e `@FimBrasil` definem o período, pela data de fechamento. O fim é **inclusivo**, por isso termina em `23:59:59`. Para um ciclo, use do dia 24 ao dia 23.
- `@MostrarDiagnostico = 0` retorna apenas o resultado final; `1` retorna informações extras para investigação.

**Consulta do painel** (`powerbi/`):

- `@PBI_QuantidadeCiclos` — quantidade de ciclos completos, padrão `12`. Cada ciclo começa às 00:00:00 do dia 24 e termina ao final do dia 23 do mês seguinte. É o único parâmetro de período, e vale apenas para esta consulta: as individuais usam `@InicioBrasil`/`@FimBrasil`.
- Feriados: vêm do **arquivo de feriados** (linhas de escopo `TODOS` ou `A2B`), pelo parâmetro `@Feriados`, nas três consultas (painel e individuais); o bloco `[S.2]` só valida e monta `#PBI_FeriadosFixos` e `#PBI_FeriadosPorData`. Datas só com fonte oficial do TCU. Passo a passo em [`docs/feriados.md`](docs/feriados.md) e [`docs/powerbi-query.md`](docs/powerbi-query.md#13-manutenção-no-power-query).

## Fluxo de validação

O fluxo esperado é:

```text
consulta SQL → resultado exportado → comparação com relatório do fornecedor → planilha em analysis/ → ajuste ou confirmação da regra
```

As planilhas de análise servem para registrar se os resultados da consulta bateram com os arquivos usados como referência.

## Convenções do projeto

- `queries/`: consultas individuais, referência técnica de cada indicador.
- `powerbi/`: consulta do painel.
- `docs/`: explicações das regras, dos cálculos e do painel, inclusive a versão HTML.
- `analysis/`: arquivos de comparação e validação.
- `project-context/`: Histórico Mestre da A2B.
- `support/`: consultas auxiliares.

Ao alterar uma regra de cálculo, atualize também a documentação correspondente em `docs/`.

Ao validar um novo ciclo, salve a planilha na pasta `analysis/`.

## Histórico Mestre

O histórico do projeto fica em
[`project-context/A2B-HISTORICO-CONTEXTO-MESTRE.md`](project-context/A2B-HISTORICO-CONTEXTO-MESTRE.md).

- Ele é **append-only**: cada intervenção vira uma seção nova, e seções antigas não são reescritas.
- Trabalhos da A2B atualizam **somente** este histórico. COI e Decision mantêm o seu, nos respectivos repositórios.
- As seções anteriores à separação dos repositórios foram herdadas do documento compartilhado da época de `Queries` e contêm registros de Decision e COI. Elas são mantidas como **legado histórico**, sem reescrita. Caminhos citados nelas (`protect4/…`, `docs/project-context/`, …) descrevem a estrutura da época.
- O arquivo se chamava `FAIA-FARC-HISTORICO-CONTEXTO-MESTRE.md`, nome herdado do documento compartilhado; foi renomeado em 2026-09-18.

