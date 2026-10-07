# Arquivo de feriados

Os feriados e pontos facultativos usados no cálculo de horas comerciais não
ficam mais dentro dos SQLs. Eles vêm de um arquivo CSV, o mesmo para Virtual,
Decision e A2B. No Power BI, o arquivo é lido do SharePoint a cada atualização:
para incluir ou tirar um feriado, basta editar o arquivo e salvar. Não é
preciso mudar o SQL nem republicar o relatório.

Este documento é **idêntico** nos três repositórios
(`Extracao_de_dados_Virtual`, `Extracao_de_dados_Decision`,
`Extracao_de_dados_A2B`).

---

## 1. Onde fica

| Uso | Arquivo |
|---|---|
| Power BI (os três relatórios) | **um** `feriados.csv` no SharePoint, no endereço configurado em `UrlArquivoFeriados` (seção 5) |
| Consultas de `queries/` | `config/feriados.csv` do repositório |

O arquivo do SharePoint é a fonte usada pelos relatórios. O `config/feriados.csv`
é a cópia versionada: guarda o histórico no Git e alimenta as consultas
executadas fora do Power BI. As cópias dos três repositórios são **idênticas**;
`tools/verificar_feriados.ps1` confere isso (seção 7). Ao mudar um feriado,
mude o SharePoint e as três cópias com o mesmo conteúdo.

Por que não um arquivo só para os três repositórios: os repositórios são
independentes e não há um diretório comum versionado. Um arquivo fora deles
não teria histórico, e um caminho de um repositório dentro de outro quebraria
quando um deles fosse clonado sozinho. Por isso há três cópias iguais,
conferidas por script.

## 2. Formato

CSV em UTF-8, com cabeçalho, separado por vírgula (ou por `;`, como o Excel em
português costuma salvar; o separador é reconhecido pelo cabeçalho):

```csv
Data,Descricao,Escopo
12-25,Natal,TODOS
2026-04-03,Paixão de Cristo,TODOS
2026-06-29,Ponto facultativo - jogo da Seleção Brasileira na Copa do Mundo FIFA 2026,DECISION;A2B
```

| Coluna | Obrigatória | Regra |
|---|---|---|
| `Data` | sim | `AAAA-MM-DD` = data única (feriado móvel, ponto facultativo). `MM-DD` = feriado fixo, vale **todo ano** (como os nacionais) |
| `Descricao` | a coluna sim; o texto pode ficar vazio | nome do feriado. Não muda o cálculo de horas; a Decision mostra o texto no diagnóstico de rotinas abertas em feriado |
| `Escopo` | sim | `TODOS`, ou um ou mais projetos separados por `;`: `VIRTUAL`, `DECISION`, `A2B` |

- Uma linha por feriado. Linhas totalmente vazias são ignoradas.
- Descrição com vírgula vai entre aspas: `"Natal, feriado nacional"`.
- O dia inteiro deixa de ter horário comercial. Não há meio expediente.
- Sábado e domingo nunca têm horário comercial; um feriado nesses dias não muda
  horas (na Decision, só o texto do diagnóstico de rotina).
- O tempo corrido (P1/P2, `Corrida`) não desconta feriado.

## 3. Por que existe a coluna Escopo

As três listas que estavam nos SQLs **não eram iguais**. Para que a mudança de
fonte não mudasse nenhum resultado, cada linha diz a que projeto vale. Hoje:

| Data | Virtual | Decision | A2B | Observação |
|---|---|---|---|---|
| feriados nacionais fixos (01-01, 04-21, 05-01, 09-07, 10-12, 11-02, 11-15, 11-20, 12-25) | sim | sim | sim | a Virtual cadastrava só 2025 e 2026; Decision e A2B, todo ano |
| 2025-03-03, 03-04, 04-17, 04-18, 05-02, 06-19 | sim | sim | **não** | a A2B cadastrava só as datas a partir de 27/10/2025 |
| 2025-03-05 (Quarta-Feira de Cinzas) | **não** (contava como dia útil) | sim | não | |
| 2025-06-20 | não | sim | não | só a Decision cadastrava |
| 2026-06-29 (Copa do Mundo) | **não** | sim | sim | Portaria-TCU nº 93/2026; a Virtual não tinha |
| demais datas de 2025-10-27 em diante | sim | sim | sim | |

Essas diferenças foram **mantidas**: harmonizar é uma decisão de regra, e muda
resultado. Para harmonizar, basta mudar o `Escopo` da linha (por exemplo,
`DECISION;A2B` → `TODOS`).

Mudanças de forma, sem efeito nos resultados publicados (conferido):

- os 9 feriados nacionais viraram `MM-DD` com `TODOS`. Para a Virtual isso
  acrescenta esses feriados nos anos fora de 2025–2026, que antes não tinham
  nenhum feriado; as populações publicadas não chegam a esses anos;
- 2025-07-20 (domingo, só na Virtual, sem descrição) saiu: domingo não tem
  horário comercial;
- 2026-04-05 (Páscoa, domingo) passou a valer também para a Virtual: domingo;
- na A2B, a consulta individual do FAIA passou a usar 24/12 e 31/12/2025, como
  o painel e a consulta do FARC já faziam. Era uma divergência registrada da
  consulta individual; com ela, 4 rotinas abertas nesses dias passam de
  0:09–0:57 para 0:00:00 de Tempo Primeiro Atendimento, o mesmo valor do
  painel publicado (nenhuma meta muda).

## 4. Como editar

1. Abrir o `feriados.csv` (no SharePoint, para o Power BI; em `config/`, para
   as consultas e o histórico).
2. Incluir uma linha por data, por exemplo
   `2027-02-08,Carnaval - ponto facultativo,TODOS`.
3. Salvar como CSV em UTF-8 (no Excel: *CSV UTF-8*). Vírgula ou `;` servem.
   Salvo em outra codificação, só as descrições com acento saem trocadas; datas
   e escopos continuam válidos.
4. Rodar `tools/verificar_feriados.ps1` no repositório (seção 7).
5. Copiar o mesmo conteúdo para o `config/feriados.csv` dos outros dois
   repositórios e para o SharePoint.

A cada ano, cadastrar as datas únicas do ano novo (feriados móveis e pontos
facultativos da portaria do TCU). Os fixos (`MM-DD`) já valem todo ano.

## 5. Power BI: leitura do SharePoint

O cálculo de horas comerciais é feito no SQL Server, que **não lê** o
SharePoint. Por isso cada relatório usa uma consulta **Power Query M**
(`powerbi/*.m`) que:

1. lê o `feriados.csv` do SharePoint (`Web.Contents`), a cada atualização;
2. valida todas as linhas (seção 6);
3. filtra as linhas do projeto (`Escopo` = `TODOS` ou o projeto);
4. envia a lista ao SQL como **parâmetro** `@Feriados` (JSON com data e
   descrição). Nenhum texto do arquivo é concatenado no SQL; o SQL valida de
   novo cada data;
5. executa a consulta (`Value.NativeQuery`) e devolve o mesmo resultado de
   antes.

O `.m` é gerado a partir do `.sql` por `tools/gerar_powerbi_m.ps1` e contém o
SQL inteiro como texto. Mudança de regra: alterar o `.sql`, gerar o `.m` de
novo e publicar uma vez. Mudança de feriado: só o arquivo do SharePoint.

**Placeholder.** No início do `.m`:

```powerquery
UrlArquivoFeriados = "INSERIR_URL_DO_ARQUIVO_FERIADOS_NO_SHAREPOINT",
```

Trocar pelo link **direto** do arquivo, no formato
`https://<empresa>.sharepoint.com/sites/<site>/Shared%20Documents/<pasta>/feriados.csv`.
No SharePoint: abrir a pasta, `...` do arquivo > *Detalhes* > *Caminho* (copiar),
ou *Abrir no aplicativo* > *Arquivo* > *Informações* > *Copiar caminho*, e tirar
o final `?web=1`, se houver. O link de compartilhamento (`/:x:/r/...`) não
serve. Enquanto o placeholder estiver no arquivo, a atualização falha com a
mensagem *Preencha UrlArquivoFeriados...*. Use o **mesmo** link nos três
relatórios.

Servidor e banco ficam na última etapa do `.m`
(`Sql.Database("bdados-14r", "mdb")`), os mesmos das consultas atuais.

**Configuração única no Power BI.**

- Credenciais: SQL Server como hoje (Windows/gateway). Para o SharePoint,
  *Conta organizacional* (OAuth2), configurada na raiz do site; no Power BI
  Desktop, em *Configurações da fonte de dados*; no serviço, em *Configurações
  do modelo semântico > Credenciais da fonte de dados*.
- Níveis de privacidade: as duas fontes como **Organizacional**. A consulta
  combina dados do SharePoint com o SQL Server; com uma das fontes como
  *Privado* (ou sem nível definido), o Power Query bloqueia a combinação. Tudo
  está numa consulta só, o que evita o erro *Formula.Firewall* de referência
  entre consultas.
- Gateway: o SQL Server é local e o SharePoint é nuvem. No gateway, habilitar
  *Permitir que as fontes de dados de nuvem do usuário sejam atualizadas por
  este cluster de gateway*, ou cadastrar a fonte Web do SharePoint no gateway.
- Consulta nativa: no Desktop, aprovar a execução da consulta nativa na
  primeira vez (e a cada mudança do SQL).

**O que não foi testado aqui.** O SQL foi executado com o parâmetro
`@Feriados` exatamente como o Power Query o envia (`sp_executesql`). O código M
não foi executado neste ambiente (não há Power BI Desktop instalado): validar
no primeiro refresh, conforme o checklist da seção 8.

## 6. Validação e falhas

Qualquer um destes problemas **interrompe** a atualização (Power BI) ou a
execução (scripts), com mensagem:

| Situação | Mensagem (resumo) |
|---|---|
| `UrlArquivoFeriados` ainda com o placeholder | *Preencha UrlArquivoFeriados...* |
| arquivo inexistente ou SharePoint inacessível | erro de acesso do Power BI / *Arquivo de feriados nao encontrado* |
| falta coluna `Data`, `Descricao` ou `Escopo` (ou separador diferente de `,` e `;`) | *Coluna(s) ausente(s)...* |
| data fora de `AAAA-MM-DD` / `MM-DD`, ou inexistente (`2026-02-30`) | *Data invalida na linha N...* |
| escopo desconhecido, vazio, ou `TODOS` junto com projeto | *Escopo invalido na linha N...* |
| nenhuma linha para o projeto | *Nenhum feriado para o projeto...* |
| consulta executada sem `@Feriados` | *Must declare the scalar variable "@Feriados"* |
| `@Feriados` vazio, JSON inválido ou truncado | *Feriados: @Feriados vazio ou invalido...* |

O relatório **nunca** é calculado com zero feriados. Data repetida no mesmo
projeto entra uma vez (vale a primeira descrição); o script avisa a repetição.

## 7. Consultas de queries/ (fora do Power BI)

O SQL Server não abre arquivos do computador do usuário, e a conta das
consultas não tem permissão de `BULK INSERT` / `OPENROWSET` (conferido em
2026-10-06: SQL Server 2016, sem `ADMINISTER BULK OPERATIONS` e com
*Ad Hoc Distributed Queries* desligado). Os feriados chegam pelo mesmo
parâmetro `@Feriados`, montado por um script PowerShell a partir de
`config/feriados.csv`:

```powershell
# executar e gravar o resultado em CSV (um arquivo por result set)
.\tools\executar_consulta.ps1 -Consulta .\queries\<consulta>.sql -Saida C:\temp\resultado

# ou gerar uma cópia da consulta, com @Feriados declarado, para abrir no SSMS
.\tools\executar_consulta.ps1 -Consulta .\queries\<consulta>.sql -GerarSql C:\temp\consulta_ssms.sql
```

- O projeto vem da linha `-- FERIADOS-ESCOPO: <PROJETO>` da própria consulta.
- `-Saida` grava `<prefixo>.rs1.csv`, `<prefixo>.rs2.csv`... em UTF-8, separado
  por `;` (abre direto no Excel em português).
- A cópia de `-GerarSql` não deve ser versionada: gere de novo sempre que o
  arquivo de feriados mudar.
- Abrir o `.sql` de `queries/` direto no SSMS, sem o script, falha com
  *Must declare the scalar variable "@Feriados"*.

Conferência do arquivo e da sincronia:

```powershell
.\tools\verificar_feriados.ps1
```

Valida o arquivo, mostra quantos feriados entram em cada projeto, compara
`config/feriados.csv`, `docs/feriados.md` e `tools/*.ps1` com os dos
repositórios irmãos (mesma pasta) e confere se cada `powerbi/*.m` corresponde ao
seu `.sql`. Termina com erro se algo não bater.

## 8. Primeiro refresh (checklist)

1. Copiar `config/feriados.csv` para a biblioteca do SharePoint escolhida.
2. Em cada relatório, criar a consulta a partir do `.m` do repositório
   (*Nova Fonte > Consulta Nula > Editor Avançado*, colar o arquivo inteiro).
3. Trocar `INSERIR_URL_DO_ARQUIVO_FERIADOS_NO_SHAREPOINT` pelo link direto do
   arquivo.
4. Credenciais: SharePoint com conta organizacional; SQL como hoje. Privacidade
   das duas fontes: Organizacional. Gateway: permitir fontes de nuvem.
5. Atualizar no Desktop e comparar com a consulta anterior: mesmo número de
   linhas e mesmos totais de FAIA e FARC.
6. Publicar e acompanhar o primeiro refresh agendado no serviço.
7. Teste de manutenção: incluir no SharePoint uma data de teste num dia útil
   recente, atualizar, ver as horas comerciais mudarem, apagar a data e
   atualizar de novo (volta ao valor anterior).
