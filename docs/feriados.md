# Arquivo de feriados

Os feriados e pontos facultativos usados no cálculo de horas comerciais não
ficam nos SQLs. Eles vêm de um arquivo CSV, **o mesmo para Virtual, Decision e
A2B**: um único calendário, o do Tribunal de Contas da União (TCU). No Power BI,
o arquivo é lido do SharePoint a cada atualização: para incluir ou tirar um
feriado, basta editar o arquivo e salvar. Não é preciso mudar o SQL nem
republicar o relatório.

Este documento é **idêntico** nos três repositórios
(`Extracao_de_dados_Virtual`, `Extracao_de_dados_Decision`,
`Extracao_de_dados_A2B`).

---

## 1. Regra

- **Fonte funcional:** a Portaria do TCU que divulga os feriados nacionais e
  define os pontos facultativos de cada ano, com todas as portarias que a
  alteram. Não se usa calendário civil genérico, de outro órgão, nem feriado
  estadual ou municipal.
- **Um calendário só.** Virtual, Decision e A2B usam exatamente a mesma lista.
  Não existe regra diferente por projeto.
- **Feriados nacionais fixos** (mesmo dia todo ano) são cadastrados **uma vez**,
  como `MM-DD`, e valem automaticamente em todos os anos.
- **Datas que mudam de ano para ano** (Carnaval, Quarta-Feira de Cinzas, Paixão
  de Cristo, Corpus Christi, emendas, véspera de Natal e de Ano Novo, Dia do
  Servidor, datas extraordinárias) são cadastradas **por ano**, como
  `AAAA-MM-DD`, conforme a Portaria daquele ano. Não se preenchem por
  suposição.
- O dia cadastrado inteiro deixa de ter horário comercial (as Portarias não
  preveem meio expediente). Sábado e domingo nunca têm horário comercial. O
  tempo corrido (P1/P2) não desconta feriado.
- O art. 2º das Portarias (feriados locais das Secretarias do TCU nos Estados)
  não entra: ele vale para as unidades estaduais, não para o calendário
  institucional usado nos contratos.

## 2. Portarias usadas (cadastro atual)

Textos obtidos do Boletim do TCU (BTCU), pela consulta de autenticidade do TCU
(`www.tcu.gov.br/autenticidade`; PDF em
`https://btcu.apps.tcu.gov.br/api/obterDocumentoPdf/<código>`).

| Ano | Portaria | Código de autenticidade | O que define |
|---|---|---|---|
| 2025 | Portaria-TCU nº 10, de 13/01/2025 | 77411949 | calendário de 2025 |
| 2025 | Portaria-TCU nº 67, de 28/04/2025 | 77981373 | inclui 02/05/2025 |
| 2025 | Portaria-TCU nº 157, de 30/10/2025 | 79190602 | inclui 21/11/2025 |
| 2025 | Portaria-TCU nº 176, de 19/12/2025 | 79506777 | inclui 26/12/2025 |
| 2026 | Portaria-TCU nº 179, de 19/12/2025 | 79506777 | define 02/01/2026 |
| 2026 | Portaria-TCU nº 1, de 08/01/2026 | 79561193 | calendário de 2026 |
| 2026 | Portaria-TCU nº 93, de 25/06/2026 | 80587034 | inclui 29/06/2026 (jogo da Seleção na Copa) |

Datas do cadastro atual (35 linhas):

- **fixas, todo ano (9):** 01-01 Confraternização Universal, 04-21 Tiradentes,
  05-01 Dia Mundial do Trabalho, 09-07 Independência do Brasil, 10-12 Nossa
  Senhora Aparecida, 11-02 Finados, 11-15 Proclamação da República, 11-20 Dia
  Nacional de Zumbi e da Consciência Negra, 12-25 Natal;
- **2025 (13):** 03/03, 04/03 (Carnaval), 05/03 (Cinzas), 17/04 (Quinta-Feira
  Santa), 18/04 (Paixão de Cristo), 02/05, 19/06 (Corpus Christi), 20/06,
  27/10 (Dia do Servidor), 21/11, 24/12, 26/12, 31/12;
- **2026 (13):** 02/01, 16/02, 17/02 (Carnaval), 18/02 (Cinzas), 02/04, 03/04
  (Paixão de Cristo), 20/04, 04/06 (Corpus Christi), 05/06, 29/06 (Copa),
  28/10 (Dia do Servidor), 24/12, 31/12.

**Pendências.** Não foi localizada alteração da Portaria nº 1/2026 posterior à
nº 93/2026 (até 07/10/2026); confirmar na base Normas do TCU antes de cada
virada de ano. Os anos anteriores a 2025 só têm os feriados fixos: as datas
móveis de 2023 e 2024 não foram cadastradas (a A2B tem chamados abertos desde
2023; ver o histórico do projeto).

## 3. Onde fica o arquivo

| Uso | Arquivo |
|---|---|
| Power BI (os três relatórios) | **um** `feriados.csv` no SharePoint, no endereço configurado em `UrlArquivoFeriados` (seção 7) |
| Consultas de `queries/` | `config/feriados.csv` do repositório |

O arquivo do SharePoint é a fonte operacional dos relatórios. O
`config/feriados.csv` é a cópia versionada: guarda o histórico no Git e
alimenta as consultas executadas fora do Power BI. As cópias dos três
repositórios são **idênticas byte a byte**; `tools/verificar_feriados.ps1`
confere isso (seção 9).

Por que três cópias e não um arquivo só nos repositórios: eles são
independentes e não há um diretório comum versionado. Um caminho de um
repositório dentro de outro quebraria quando um deles fosse clonado sozinho.

## 4. Formato

CSV em UTF-8, com cabeçalho, separado por vírgula (ou por `;`, como o Excel em
português costuma salvar; o separador é reconhecido pelo cabeçalho):

```csv
Data,Descricao,Fonte
12-25,Natal,Feriado nacional fixo; Portarias-TCU nº 10/2025 e nº 1/2026
2026-06-29,Ponto facultativo - jogo da Seleção Brasileira na Copa do Mundo FIFA 2026,"Portaria-TCU nº 93/2026 (BTCU, autenticidade 80587034)"
```

| Coluna | Regra |
|---|---|
| `Data` | `MM-DD` = feriado nacional fixo, todo ano; `AAAA-MM-DD` = data de um ano |
| `Descricao` | nome do feriado ou ponto facultativo. Não muda o cálculo de horas; a Decision mostra o texto no diagnóstico de rotinas abertas em feriado |
| `Fonte` | a Portaria do TCU (número, ano e código de autenticidade). Não entra no cálculo; `tools/verificar_feriados.ps1` recusa linha sem fonte |

- Uma linha por data. Linhas totalmente vazias são ignoradas.
- Texto com vírgula vai entre aspas: `"Portaria-TCU nº 10/2025 (BTCU, ...)"`.
- Não existe coluna `Escopo`: até 2026-10-07 ela separava listas por projeto;
  foi removida com o calendário único.

## 5. Quando sair uma nova Portaria do TCU

1. Abrir o `feriados.csv` (o do SharePoint e o `config/feriados.csv`).
2. Adicionar **apenas** as datas do ano previstas na Portaria, como
   `AAAA-MM-DD`: feriados móveis e pontos facultativos.
3. **Não** repetir os feriados nacionais fixos: as linhas `MM-DD` já valem
   para o ano novo.
4. Registrar a Portaria na coluna `Fonte` (número, data e código de
   autenticidade do BTCU).
5. Se a Portaria for **alterada** durante o ano, incluir ou retirar as datas
   correspondentes, citando a portaria de alteração.
6. Rodar `.\tools\verificar_feriados.ps1` num dos repositórios e copiar o mesmo
   arquivo para o `config/feriados.csv` dos outros dois.
7. Salvar o arquivo no SharePoint. A próxima atualização dos três relatórios já
   usa a lista nova.

Salve como CSV em UTF-8 (no Excel: *CSV UTF-8*). Vírgula ou `;` servem. Salvo
em outra codificação, só os textos com acento saem trocados; as datas continuam
válidas.

## 6. Validação e falhas

Qualquer um destes problemas **interrompe** a atualização (Power BI) ou a
execução (scripts), com mensagem:

| Situação | Mensagem (resumo) |
|---|---|
| `UrlArquivoFeriados` ainda com o placeholder | *Preencha UrlArquivoFeriados...* |
| arquivo inexistente ou SharePoint inacessível | erro do `Web.Contents` (ex.: 404) / *Arquivo de feriados nao encontrado* |
| falta coluna `Data`, `Descricao` ou `Fonte` (ou separador diferente de `,` e `;`) | *Coluna(s) ausente(s)...* |
| `Data` fora de `MM-DD` / `AAAA-MM-DD`, ou inexistente (`2026-02-30`, `26/12/2026`) | *Data invalida na linha N...* |
| arquivo sem nenhuma data | *Nenhum feriado no arquivo de feriados* |
| consulta executada sem `@Feriados` | *Must declare the scalar variable "@Feriados"* |
| `@Feriados` vazio, JSON inválido ou truncado | *Feriados: @Feriados vazio ou invalido...* |

O relatório **nunca** é calculado com zero feriados. Data repetida entra uma
vez (vale a primeira descrição); o script avisa a repetição.

## 7. Power BI: leitura do SharePoint

O cálculo de horas comerciais é feito no SQL Server, que **não lê** o
SharePoint. Cada relatório usa uma consulta **Power Query M** (`powerbi/*.m`)
que:

1. lê o `feriados.csv` do SharePoint (`Web.Contents`, URL direta), a cada
   atualização;
2. valida todas as linhas (seção 6);
3. envia a lista ao SQL como **parâmetro** `@Feriados` (JSON com data e
   descrição). Nenhum texto do arquivo é concatenado no SQL; o SQL valida de
   novo cada data;
4. executa a consulta (`Value.NativeQuery`) e devolve o mesmo resultado do SQL.

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
serve. Use o **mesmo** link nos três relatórios. Servidor e banco ficam no fim
do `.m` (`Sql.Database("bdados-14r", "mdb")`): conferir se são os mesmos da
fonte atual do PBIX.

**Formula.Firewall.** A primeira versão do `.m` gerado (commits de
2026-10-07, antes desta correção) produzia o erro *Formula.Firewall* ("faz
referência a outras consultas ou etapas, portanto, pode não ter acesso direto a
uma fonte de dados"), mesmo com as duas fontes como Organizacional: cada etapa
era um passo separado, e o passo final acessava o SQL usando dados de passos
que acessavam o SharePoint. O `.m` foi reestruturado para um **único passo**
(`Fonte`), em que as duas fontes ficam na mesma partição do firewall e ele só
confere se os níveis de privacidade são compatíveis. Não separe os passos.

**Configuração única no Power BI.**

- **Privacidade:** SharePoint = **Organizacional**; SQL Server =
  **Organizacional**. Com uma das fontes Privada ou Pública, ou sem nível
  definido, o Power Query recusa a combinação. Não é preciso (nem recomendado)
  ignorar os níveis de privacidade.
- **Credenciais:** SQL Server como hoje (Windows/gateway); SharePoint com
  *Conta organizacional* (OAuth2). No Desktop, em *Configurações da fonte de
  dados*; no serviço, em *Configurações do modelo semântico > Credenciais da
  fonte de dados* (se o teste de conexão falhar na raiz do site, marcar
  *Ignorar conexão de teste*).
- **Gateway:** o SQL Server é local e precisa de gateway. O SharePoint Online é
  fonte de nuvem. Como a mesma consulta combina as duas, ela é avaliada no
  gateway: habilitar *Permitir que as fontes de dados de nuvem do usuário sejam
  atualizadas por este cluster de gateway* (ou cadastrar a fonte Web do
  SharePoint no gateway), e a máquina do gateway precisa acessar o SharePoint
  Online.
- **Consulta nativa:** no Desktop, aprovar a execução da consulta nativa na
  primeira vez (e a cada mudança do SQL).

**O que foi validado (2026-10-07)**, com o motor de Power Query do Power BI
Desktop instalado nesta máquina, fora de qualquer PBIX, com o arquivo servido
por HTTP local e só o placeholder trocado:

- os três `.m` executam com SharePoint/Web e SQL como Organizacional, firewall
  de privacidade ativo, sem ignorar níveis de privacidade;
- resultado do M = resultado do SQL nos três projetos: mesmas linhas, colunas,
  ordem e valores;
- Privado ou Público em qualquer das fontes, ou nível não definido: a
  combinação é recusada (o firewall continua ativo);
- todas as falhas da seção 6; `;` com BOM; deduplicação; lista de ~26 mil
  caracteres sem truncamento.

**O que ainda depende do ambiente real:** acesso ao SharePoint Online com
OAuth2, o PBIX, o gateway do workspace e o refresh agendado no Power BI
Service. Ver o checklist da seção 10.

## 8. Consultas de queries/ (fora do Power BI)

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

- `-Saida` grava `<prefixo>.rs1.csv`, `<prefixo>.rs2.csv`... em UTF-8, separado
  por `;` (abre direto no Excel em português).
- A cópia de `-GerarSql` não deve ser versionada: gere de novo sempre que o
  arquivo de feriados mudar.
- Abrir o `.sql` de `queries/` direto no SSMS, sem o script, falha com
  *Must declare the scalar variable "@Feriados"*.

## 9. Conferência do arquivo e da sincronia

```powershell
.\tools\verificar_feriados.ps1
```

Valida o arquivo, exige `Fonte` preenchida, mostra quantos feriados fixos e
quantas datas por ano ele tem, compara `config/feriados.csv`,
`docs/feriados.md` e `tools/*.ps1` com os dos repositórios irmãos (mesma pasta)
e confere se cada `powerbi/*.m` corresponde ao seu `.sql`. Termina com erro se
algo não bater.

## 10. Primeiro refresh (checklist)

1. Copiar `config/feriados.csv` para a biblioteca do SharePoint escolhida.
2. Em cada relatório, criar a consulta a partir do `.m` do repositório
   (*Nova Fonte > Consulta Nula > Editor Avançado*, colar o arquivo inteiro).
3. Trocar `INSERIR_URL_DO_ARQUIVO_FERIADOS_NO_SHAREPOINT` pelo link direto do
   arquivo.
4. Credenciais: SharePoint com conta organizacional; SQL como hoje. Privacidade
   das duas fontes: Organizacional. Gateway: permitir fontes de nuvem.
5. Atualizar no Desktop e conferir o número de linhas e os totais de FAIA e
   FARC com os valores esperados do calendário TCU (ver o histórico do
   projeto).
6. Publicar e acompanhar o primeiro refresh agendado no serviço.
7. Teste de manutenção: incluir no SharePoint uma data de teste num dia útil
   recente, atualizar, ver as horas comerciais mudarem, apagar a data e
   atualizar de novo (volta ao valor anterior).

## 11. Histórico

- **2026-10-06/07:** listas tiradas dos SQLs; arquivo com coluna `Escopo`, que
  preservava as diferenças entre as listas antigas de cada projeto.
- **2026-10-07 (correção):** calendário único do TCU para os três projetos,
  conferido contra as Portarias da seção 2; coluna `Escopo` removida; coluna
  `Fonte` incluída; `.m` reestruturado para um único passo (Formula.Firewall).
  O impacto em cada projeto está no histórico do repositório
  (`project-context/`).
