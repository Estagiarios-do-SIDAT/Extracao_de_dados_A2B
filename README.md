# Extração de dados — A2B / Protect4

Repositório com consultas SQL, documentações e planilhas de validação usadas para apurar os indicadores **FAIA** e **FARC** da **A2B / Protect4** a partir da base do **CA Service Desk Manager**.

O objetivo do projeto é manter, em um só lugar, as consultas usadas na apuração dos indicadores, a explicação das regras aplicadas e os arquivos de conferência contra os relatórios recebidos.

Este repositório atende **somente a A2B / Protect4**. COI e Decision têm repositórios próprios (`Extracao_de_dados_COI` e `Extracao_de_dados_Decision`) e nada deles vive aqui. A antiga pasta `Queries`, onde os três núcleos conviviam, **não é mais fonte operacional** — desde 2026-09-18 a fonte oficial da A2B é este repositório.

## Estrutura do repositório

```text
.
├── protect4/
│   ├── queries/
│   │   ├── consulta_faia_a2b_protect4.sql
│   │   └── consulta_farc_a2b_protect4.sql
│   ├── powerbi/
│   │   └── consulta_faia_farc_power_bi.sql
│   ├── docs/
│   │   ├── faia-calculation.md
│   │   ├── farc-calculation.md
│   │   └── powerbi-query.md
│   └── analysis/
│       └── planilhas de comparação
│
├── docs/
│   └── project-context/
│       └── FAIA-FARC-HISTORICO-CONTEXTO-MESTRE.md   Histórico Mestre da A2B
│
├── support/
│   ├── consulta_logs_chamados_listados.sql
│   ├── consulta_status_chamados.sql
│   ├── consulta_status_hold.sql
│   └── consulta_tipos_chamado.sql
│
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

**`protect4/queries/` — consultas individuais.** São as **referências técnicas** de cada indicador. É onde a regra de cálculo mora e é o que se consulta quando há dúvida sobre um número.

| Arquivo | Finalidade |
|---|---|
| `protect4/queries/consulta_faia_a2b_protect4.sql` | Calcula o FAIA da A2B/Protect4 |
| `protect4/queries/consulta_farc_a2b_protect4.sql` | Calcula o FARC da A2B/Protect4 |

**`protect4/powerbi/` — consulta consolidada do painel.** Reúne os dois indicadores para consumo pelo Power BI.

| Arquivo | Finalidade |
|---|---|
| `protect4/powerbi/consulta_faia_farc_power_bi.sql` | FAIA e FARC juntos, para o painel |

Ela:

- reúne FAIA e FARC do mesmo chamado na **mesma linha**;
- retorna **uma linha por chamado**;
- **não repete** as colunas compartilhadas do chamado;
- mantém as colunas específicas de cada indicador;
- foi estruturada para consumo pelo Power BI (um único resultado, sem `GO`, sem diagnósticos, tipos nativos);
- usa `nHR_FAIA` e `nHR_FARC` **proporcionais e decimais**;
- cobre automaticamente os **seis últimos ciclos completos**.

> A consulta consolidada **não substitui** as consultas individuais como referência técnica. Ela reaproveita os mesmos motores de cálculo; não reimplementa nenhuma regra.

**`protect4/docs/` — explicações.**

```text
protect4/docs/faia-calculation.md    como o FAIA é calculado
protect4/docs/farc-calculation.md    como o FARC é calculado
protect4/docs/powerbi-query.md       colunas e uso da consulta do painel
```

[Documentação da consulta consolidada do Power BI](protect4/docs/powerbi-query.md)

As planilhas em `protect4/analysis/` guardam as comparações usadas na validação dos resultados.

## Consultas de apoio

A pasta `support/` contém consultas auxiliares usadas durante análise e depuração.

| Arquivo | Uso |
|---|---|
| `support/consulta_logs_chamados_listados.sql` | Lista todos os logs dos chamados informados |
| `support/consulta_status_chamados.sql` | Lista os status cadastrados no SDM |
| `support/consulta_status_hold.sql` | Mostra cada status e o flag `cr_stat.hold`, que indica se ele para o relógio do SLA |
| `support/consulta_tipos_chamado.sql` | Lista os tipos de chamado e suas quantidades |

Essas consultas não calculam FAIA nem FARC. Elas servem para investigar chamados, conferir códigos e entender registros da base.

## Como usar as consultas

1. Abra o arquivo SQL do fornecedor e indicador desejado.
2. Ajuste o período de apuração nos parâmetros de data.
3. Mantenha `@MostrarDiagnostico = 0` para uso normal no relatório.
4. Execute a consulta na base `mdb`.
5. Exporte o resultado.
6. Compare com os arquivos recebidos do fornecedor.
7. Salve a análise na pasta `analysis/` correspondente.

Quando houver divergência, use `@MostrarDiagnostico = 1` para retornar tabelas intermediárias de conferência.

## Parâmetros comuns

As consultas normalmente possuem parâmetros como:

```sql
DECLARE @InicioBrasil datetime2(0)
DECLARE @FimBrasil    datetime2(0)
DECLARE @MostrarDiagnostico bit = 0
```

- `@InicioBrasil` e `@FimBrasil` definem o período analisado.
- `@MostrarDiagnostico = 0` retorna apenas o resultado final.
- `@MostrarDiagnostico = 1` retorna informações extras para investigação.

## Fluxo de validação

O fluxo esperado é:

```text
consulta SQL → resultado exportado → comparação com relatório do fornecedor → planilha em analysis/ → ajuste ou confirmação da regra
```

As planilhas de análise servem para registrar se os resultados da consulta bateram com os arquivos usados como referência.

## Convenções do projeto

- `protect4/queries/`: consultas executáveis do indicador da A2B/Protect4.
- `protect4/docs/`: explicações das regras e dos cálculos.
- `protect4/analysis/`: arquivos de comparação e validação.
- `support/`: consultas auxiliares.

Ao alterar uma regra de cálculo, atualize também a documentação correspondente em `protect4/docs/`.

Ao validar um novo ciclo, salve a planilha na pasta `protect4/analysis/`.

## Histórico Mestre

O histórico do projeto fica em
[`docs/project-context/FAIA-FARC-HISTORICO-CONTEXTO-MESTRE.md`](docs/project-context/FAIA-FARC-HISTORICO-CONTEXTO-MESTRE.md).

- Ele é **append-only**: cada intervenção vira uma seção nova, e seções antigas não são reescritas.
- Trabalhos da A2B atualizam **somente** este histórico. COI e Decision mantêm o seu, nos respectivos repositórios.
- As seções anteriores à separação dos repositórios foram herdadas do documento compartilhado da época de `Queries` e contêm registros de Decision e COI. Elas são mantidas como **legado histórico**, sem reescrita.

