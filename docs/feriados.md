# Arquivo de feriados

Os feriados e pontos facultativos usados no cálculo do **Horário TCU** não ficam
nos SQLs. Eles vêm de um arquivo de texto, **`docs/feriados.txt`**, que é o
mesmo para Virtual, Decision e A2B: um único calendário, o do Tribunal de
Contas da União (TCU). No Power BI, o arquivo é lido do SharePoint a cada
atualização: para incluir ou tirar uma data, basta editar o arquivo e salvar.
Não é preciso mudar o SQL nem republicar o relatório.

`docs/feriados.txt` é o calendário editável. Este documento explica as regras,
o formato, as fontes e a integração. Ele é **idêntico** nos três repositórios
que usam o calendário (`Extracao_de_dados_Virtual`,
`Extracao_de_dados_Decision`, `Extracao_de_dados_A2B`).

---

## 1. Regra

- **Fonte funcional:** a Portaria do TCU que divulga os feriados nacionais e
  define os pontos facultativos de cada ano, com todas as portarias que a
  alteram. Não se usa calendário civil genérico, de outro órgão, nem feriado
  estadual ou municipal.
- **Um calendário só.** Virtual, Decision e A2B usam exatamente a mesma lista.
  Não existe regra diferente por projeto.
- **Feriados nacionais fixos** (mesmo dia todo ano) são cadastrados **uma vez**,
  como `DD-MM`, e valem automaticamente em todos os anos.
- **Datas que mudam de ano para ano** (Carnaval, Quarta-Feira de Cinzas, Paixão
  de Cristo, Corpus Christi, emendas, véspera de Natal e de Ano Novo, Dia do
  Servidor, datas extraordinárias) são cadastradas **por ano**, como
  `DD-MM-AAAA`, conforme a Portaria daquele ano. Não se preenchem por
  suposição.
- O dia cadastrado inteiro fica fora do Horário TCU (as Portarias não preveem
  meio expediente). Sábado e domingo nunca estão no Horário TCU. A contagem
  24x7 (P1/P2) não desconta feriado.
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

Datas do cadastro atual (35), por seção do `feriados.txt`:

| Seção | Data | Nome | Fonte |
|---|---|---|---|
| Feriados Fixos | 01-01 | Confraternização Universal | Portarias-TCU nº 10/2025 e nº 1/2026 |
| Feriados Fixos | 21-04 | Tiradentes | idem |
| Feriados Fixos | 01-05 | Dia Mundial do Trabalho | idem |
| Feriados Fixos | 07-09 | Independência do Brasil | idem |
| Feriados Fixos | 12-10 | Nossa Senhora Aparecida | idem |
| Feriados Fixos | 02-11 | Finados | idem |
| Feriados Fixos | 15-11 | Proclamação da República | idem |
| Feriados Fixos | 20-11 | Dia Nacional de Zumbi e da Consciência Negra | idem |
| Feriados Fixos | 25-12 | Natal | idem |
| Feriados móveis/diferenciados | 18-04-2025 | Paixão de Cristo | Portaria-TCU nº 10/2025 |
| Feriados móveis/diferenciados | 03-04-2026 | Paixão de Cristo | Portaria-TCU nº 1/2026 |
| Pontos Facultativos | 03-03-2025, 04-03-2025 | Carnaval | Portaria-TCU nº 10/2025 |
| Pontos Facultativos | 05-03-2025 | Quarta-Feira de Cinzas | Portaria-TCU nº 10/2025 |
| Pontos Facultativos | 17-04-2025 | Quinta-Feira Santa | Portaria-TCU nº 10/2025 |
| Pontos Facultativos | 02-05-2025 | sexta-feira após o Dia Mundial do Trabalho | Portaria-TCU nº 67/2025 |
| Pontos Facultativos | 19-06-2025 | Corpus Christi | Portaria-TCU nº 10/2025 |
| Pontos Facultativos | 20-06-2025 | sexta-feira após Corpus Christi | Portaria-TCU nº 10/2025 |
| Pontos Facultativos | 27-10-2025 | Dia do Servidor Público federal | Portaria-TCU nº 10/2025 |
| Pontos Facultativos | 21-11-2025 | sexta-feira após a Consciência Negra | Portaria-TCU nº 157/2025 |
| Pontos Facultativos | 24-12-2025 | véspera do Natal | Portaria-TCU nº 10/2025 |
| Pontos Facultativos | 26-12-2025 | sexta-feira após o Natal | Portaria-TCU nº 176/2025 |
| Pontos Facultativos | 31-12-2025 | véspera da Confraternização Universal | Portaria-TCU nº 10/2025 |
| Pontos Facultativos | 02-01-2026 | emenda após a Confraternização Universal | Portarias-TCU nº 1/2026 e nº 179/2025 |
| Pontos Facultativos | 16-02-2026, 17-02-2026 | Carnaval | Portaria-TCU nº 1/2026 |
| Pontos Facultativos | 18-02-2026 | Quarta-Feira de Cinzas | Portaria-TCU nº 1/2026 |
| Pontos Facultativos | 02-04-2026 | véspera da Paixão de Cristo | Portaria-TCU nº 1/2026 |
| Pontos Facultativos | 20-04-2026 | emenda antes de Tiradentes | Portaria-TCU nº 1/2026 |
| Pontos Facultativos | 04-06-2026 | Corpus Christi | Portaria-TCU nº 1/2026 |
| Pontos Facultativos | 05-06-2026 | emenda após Corpus Christi | Portaria-TCU nº 1/2026 |
| Pontos Facultativos | 29-06-2026 | jogo da Seleção Brasileira na Copa do Mundo FIFA 2026 | Portaria-TCU nº 93/2026 |
| Pontos Facultativos | 28-10-2026 | Dia do Servidor Público federal | Portaria-TCU nº 1/2026 |
| Pontos Facultativos | 24-12-2026 | véspera do Natal | Portaria-TCU nº 1/2026 |
| Pontos Facultativos | 31-12-2026 | véspera da Confraternização Universal | Portaria-TCU nº 1/2026 |

A seção **Feriados Por Data** existe para feriados de um único dia que não
sejam móveis nem ponto facultativo; hoje não tem nenhuma data.

**Pendências.** Não foi localizada alteração da Portaria nº 1/2026 posterior à
nº 93/2026 (até 07/10/2026); confirmar na base Normas do TCU antes de cada
virada de ano. Os anos anteriores a 2025 só têm os feriados fixos: as datas
móveis de 2023 e 2024 não foram cadastradas (a A2B tem chamados abertos desde
2023; ver o histórico do projeto).

## 3. Onde fica o arquivo

| Uso | Arquivo |
|---|---|
| Power BI (os três relatórios) | **um** `feriados.txt` no SharePoint, no endereço configurado em `UrlArquivoFeriados` (seção 7) |
| Consultas de `queries/` | `docs/feriados.txt` do próprio repositório |
| Consulta humana | cópias idênticas em `Extracao_de_dados_COI/docs/feriados.txt` e em `Documentos e Relatórios/feriados.txt` |

O arquivo do SharePoint é a fonte operacional dos relatórios. O
`docs/feriados.txt` de cada repositório é a cópia versionada: guarda o
histórico no Git e alimenta as consultas executadas fora do Power BI. Cada
repositório usa **só a sua cópia**; nenhuma consulta lê o arquivo do COI ou de
`Documentos e Relatórios`. Todas as cópias são **idênticas byte a byte**;
`tools/verificar_feriados.ps1` confere isso (seção 9).

Por que várias cópias e não um arquivo só: os repositórios são independentes e
não há um diretório comum versionado. Um caminho de um repositório dentro de
outro quebraria quando um deles fosse clonado sozinho.

## 4. Formato

Texto simples em **UTF-8**, organizado em seções que começam com `## `:

```text
## Regras
(texto explicativo)

## Feriados Fixos
Formato: DD-MM.
01-01
25-12

## Feriados Por Data
Formato: DD-MM-AAAA.

## Feriados móveis/diferenciados
Formato: DD-MM-AAAA.
03-04-2026

## Pontos Facultativos
Formato: DD-MM-AAAA.
02-01-2026
```

Regras de leitura (iguais no PowerShell e no Power Query):

| Linha | Tratamento |
|---|---|
| só `DD-MM` (ex.: `25-12`) | feriado fixo; precisa estar em `## Feriados Fixos` |
| só `DD-MM-AAAA` (ex.: `03-04-2026`) | data de um ano; precisa estar em `## Feriados Por Data`, `## Feriados móveis/diferenciados` ou `## Pontos Facultativos` |
| `## <nome>` | início de seção; o nome precisa ser um dos cinco acima (sem diferença de maiúsculas e acentos) |
| qualquer outra (títulos, parágrafos, linhas vazias) | ignorada |

- Uma data por linha, sem texto na mesma linha. Nomes e fontes ficam em
  parágrafos dentro das seções e na tabela da seção 2.
- Espaços nas pontas da linha são ignorados. Fim de linha LF ou CRLF, com ou
  sem BOM.
- Internamente as datas são convertidas para o formato do SQL: `DD-MM` →
  `MM-DD`, `DD-MM-AAAA` → `AAAA-MM-DD` (seção 7).

## 5. Quando sair uma nova Portaria do TCU

1. Abrir o `feriados.txt` (o do SharePoint e o `docs/feriados.txt`).
2. Adicionar **apenas** as datas do ano previstas na Portaria, como
   `DD-MM-AAAA`, na seção certa: `## Feriados móveis/diferenciados` (Paixão de
   Cristo e outros feriados de data variável) ou `## Pontos Facultativos`.
3. **Não** repetir os feriados nacionais fixos: as linhas `DD-MM` já valem para
   o ano novo.
4. Acrescentar, antes das datas, uma linha com o ano e a Portaria (número, data
   e código de autenticidade do BTCU), e atualizar a tabela da seção 2 deste
   documento.
5. Se a Portaria for **alterada** durante o ano, incluir ou retirar as datas
   correspondentes, citando a portaria de alteração.
6. Rodar `.\tools\verificar_feriados.ps1` num dos repositórios e copiar o mesmo
   arquivo para o `docs/feriados.txt` dos outros repositórios (inclusive o
   COI) e para `Documentos e Relatórios/feriados.txt`.
7. Salvar o arquivo no SharePoint. A próxima atualização dos três relatórios já
   usa a lista nova.

## 6. Validação e falhas

Qualquer um destes problemas **interrompe** a atualização (Power BI) ou a
execução (scripts), com a mensagem e o número da linha:

| Situação | Mensagem (resumo) |
|---|---|
| `UrlArquivoFeriados` ainda com o placeholder | *Preencha UrlArquivoFeriados...* |
| arquivo inexistente ou SharePoint inacessível | erro do `Web.Contents` (ex.: 404) / *Arquivo de feriados nao encontrado* |
| arquivo vazio | *Arquivo de feriados vazio* |
| arquivo em outra codificação (UTF-16, ANSI com acento) | *Arquivo de feriados com codificacao invalida* |
| data inexistente (`31-02-2026`, `31-02`) | *linha N: data invalida...* |
| linha que parece data fora do formato (`2026-04-03`, `3-4-2026`, `03/04/2026`) | *linha N: formato invalido...* |
| mesma data duas vezes | *linha N: data ... repetida* |
| `DD-MM` fora de `## Feriados Fixos`, ou `DD-MM-AAAA` fora das seções com ano | *linha N: ... fora da secao...* |
| título `## ` com nome desconhecido | *linha N: secao desconhecida...* |
| arquivo sem nenhuma data | *Arquivo de feriados sem nenhuma data* |
| consulta executada sem `@Feriados` | *Must declare the scalar variable "@Feriados"* |
| `@Feriados` vazio, JSON inválido ou truncado | *Feriados: @Feriados vazio ou invalido...* |

O relatório **nunca** é calculado com zero feriados. Uma data com ano que cai
num feriado fixo (por exemplo `25-12-2026`) não é erro nem conta duas vezes;
`tools/verificar_feriados.ps1` avisa a redundância.

## 7. Power BI: leitura do SharePoint

O cálculo do Horário TCU é feito no SQL Server, que **não lê** o SharePoint.
Cada relatório usa uma consulta **Power Query M** (`powerbi/*.m`) que:

1. lê o `feriados.txt` do SharePoint (`Web.Contents`, URL direta), a cada
   atualização;
2. valida todas as linhas (seções 4 e 6);
3. envia a lista ao SQL como **parâmetro** `@Feriados`: JSON com `data`
   (`MM-DD` para os fixos, `AAAA-MM-DD` para as datas com ano) e `descricao`
   (o nome da seção: `Feriado fixo`, `Feriado por data`,
   `Feriado móvel/diferenciado` ou `Ponto facultativo`). Nenhum texto do
   arquivo é concatenado no SQL; o SQL valida de novo cada data;
4. executa a consulta (`Value.NativeQuery`) e devolve o mesmo resultado do SQL.

O `.m` é gerado a partir do `.sql` por `tools/gerar_powerbi_m.ps1` e contém o
SQL inteiro como texto. Mudança de regra: alterar o `.sql`, gerar o `.m` de
novo e publicar uma vez. Mudança de feriado: só o arquivo do SharePoint.

**Placeholder.** No início do `.m`:

```powerquery
UrlArquivoFeriados = "INSERIR_URL_DO_ARQUIVO_FERIADOS_NO_SHAREPOINT",
```

Trocar pelo link **direto** do arquivo, no formato
`https://<empresa>.sharepoint.com/sites/<site>/Shared%20Documents/<pasta>/feriados.txt`.
No SharePoint: abrir a pasta, `...` do arquivo > *Detalhes* > *Caminho*
(copiar), e tirar o final `?web=1`, se houver. O link de compartilhamento
(`/:t:/r/...`) não serve. Use o **mesmo** link nos três relatórios. Servidor e
banco ficam no fim do `.m` (`Sql.Database("bdados-14r", "mdb")`): conferir se
são os mesmos da fonte atual do PBIX.

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

**O que foi validado**, com o motor de Power Query do Power BI Desktop
instalado nesta máquina, fora de qualquer PBIX, com o arquivo servido por HTTP
local e só o placeholder trocado:

- (2026-10-07, CSV) os três `.m` executam com SharePoint/Web e SQL como
  Organizacional, firewall de privacidade ativo, sem ignorar níveis de
  privacidade; Privado ou Público em qualquer das fontes, ou nível não
  definido, são recusados;
- (2026-10-07, TXT) a leitura do `feriados.txt` no M gera o mesmo JSON do
  `tools/feriados.ps1` (mesmas datas, descrições e ordem); todas as falhas da
  seção 6 param a atualização; BOM e CRLF são aceitos; resultado do M =
  resultado do SQL nos três projetos.

**O que ainda depende do ambiente real:** acesso ao SharePoint Online com
OAuth2, o PBIX, o gateway do workspace e o refresh agendado no Power BI
Service. Ver o checklist da seção 10.

## 8. Consultas de queries/ (fora do Power BI)

O SQL Server não abre arquivos do computador do usuário, e a conta das
consultas não tem permissão de `BULK INSERT` / `OPENROWSET` (conferido em
2026-10-06: SQL Server 2016, sem `ADMINISTER BULK OPERATIONS` e com
*Ad Hoc Distributed Queries* desligado). Os feriados chegam pelo mesmo
parâmetro `@Feriados`, montado por um script PowerShell a partir de
`docs/feriados.txt`:

```powershell
# executar e gravar o resultado em CSV (um arquivo por result set)
.\tools\executar_consulta.ps1 -Consulta .\queries\<consulta>.sql -Saida C:\temp\resultado

# ou gerar uma cópia da consulta, com @Feriados declarado, para abrir no SSMS
.\tools\executar_consulta.ps1 -Consulta .\queries\<consulta>.sql -GerarSql C:\temp\consulta_ssms.sql
```

- `-Saida` grava `<prefixo>.rs1.csv`, `<prefixo>.rs2.csv`... em UTF-8, separado
  por `;` (abre direto no Excel em português). Esse CSV é o **resultado** da
  consulta, não o calendário.
- A cópia de `-GerarSql` não deve ser versionada: gere de novo sempre que o
  arquivo de feriados mudar.
- Abrir o `.sql` de `queries/` direto no SSMS, sem o script, falha com
  *Must declare the scalar variable "@Feriados"*.

## 9. Conferência do arquivo e da sincronia

```powershell
.\tools\verificar_feriados.ps1
```

Valida o arquivo, mostra quantas datas ele tem por seção e por ano, avisa
redundâncias, compara `docs/feriados.txt`, `docs/feriados.md` e `tools/*.ps1`
com os dos repositórios irmãos (mesma pasta), compara o `feriados.txt` com as
cópias do COI e de `Documentos e Relatórios` (se existirem) e confere se cada
`powerbi/*.m` corresponde ao seu `.sql`. Termina com erro se algo não bater.

## 10. Primeiro refresh (checklist)

1. Copiar `docs/feriados.txt` para a biblioteca do SharePoint escolhida.
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
   recente, atualizar, ver as horas no Horário TCU mudarem, apagar a data e
   atualizar de novo (volta ao valor anterior).

## 11. Histórico

- **2026-10-06/07:** listas tiradas dos SQLs; arquivo com coluna `Escopo`, que
  preservava as diferenças entre as listas antigas de cada projeto.
- **2026-10-07 (correção):** calendário único do TCU para os três projetos,
  conferido contra as Portarias da seção 2; coluna `Escopo` removida; coluna
  `Fonte` incluída; `.m` reestruturado para um único passo (Formula.Firewall).
- **2026-10-07 (TXT):** `config/feriados.csv` (`Data,Descricao,Fonte`)
  substituído por `docs/feriados.txt`, em seções e com datas em `DD-MM` e
  `DD-MM-AAAA`; mesmas 35 datas, sem perda nem acréscimo. Nomes e fontes de
  cada data passaram para a seção 2 deste documento e para os parágrafos do
  próprio arquivo. A descrição enviada ao SQL passou a ser o nome da seção (na
  Decision ela só aparece no diagnóstico de rotina aberta em feriado). Cópias
  também no COI e em `Documentos e Relatórios`. O impacto em cada projeto está
  no histórico do repositório (`project-context/`).
