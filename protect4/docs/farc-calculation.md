# FARC - Como o Tempo de Atendimento é calculado

Explicação simples de como a consulta `consulta\_farc\_a2b\_protect4.sql` chega no Tempo de Atendimento de cada chamado. Cada passo tem a explicação em linguagem do dia a dia e, logo abaixo, o trecho real do SQL que faz aquilo.

A ideia central: o Tempo de Atendimento é como um **cronômetro** que só fica ligado nos pedaços em que a A2B está cuidando do chamado. Não é "fim menos começo"; é a soma dos pedaços que valem.

\---

## 1\. Quais chamados entram

Só entra o chamado fechado, no período, do grupo A2B, do tipo Incidente/Solicitação/Problema e que terminou em um status de encerramento (por código, não por texto).

No SQL:

```sql
INSERT INTO #EscopoIds(id, FonteFornecedor)
SELECT b.id, N'Grupo atual A2B/Protect4'
FROM #Base AS b
WHERE b.group\_id = @FornecedorGrupo
  AND b.\[type] IN ('I', 'R', 'P')
  AND b.status IN (
        'CL','CLD','CLUNRSLV','CNCL','ATGR','END','PC','RE','VARES'
      );
```

O filtro de "fechado no período" já foi aplicado antes, ao montar `#CRPeriodo` (`close\_date` preenchida e dentro do intervalo).

\---

## 2\. Quando o cronômetro começa

O começo não é quando o chamado nasceu, e sim quando ele **entra na posse da A2B**. Se não houver registro dessa entrada, usa-se a abertura.

No SQL (tabela `#InicioContagemA2B`):

```sql
COALESCE(eg.entrada\_grupo\_epoch, b.open\_date) AS inicio\_contagem\_epoch
```

`eg.entrada\_grupo\_epoch` é a transferência para a A2B, achada no histórico de grupo (`View\_Audit\_Group`, `audit\_log` ou o texto do `act\_log`).

\---

## 3\. A captura (primeiro "Em andamento")

A captura é a primeira vez que o chamado vai para "Em andamento" depois de entrar na A2B. Cuidado: linhas como "Em andamento -> Agendado" também contêm o texto "Em andamento", então o filtro exige o destino exato.

No SQL (tabela `#CapturaStatus`):

```sql
WHERE al.system\_time >= ic.inicio\_contagem\_epoch
  AND al.type = 'ST'
  AND txt.texto\_log COLLATE Latin1\_General\_CI\_AI
        LIKE N'%Status alterado de%para ''Em andamento''%'
```

\---

## 4\. Quando o cronômetro desliga (o Terminal)

O Terminal é onde o cronômetro para de vez. Ele para na **hora em que o chamado foi resolvido**, desde que essa hora faça sentido: ela existe, é depois do começo e não passa do fechamento. Se não fizer sentido (ou não existir), para na **hora do fechamento**.

Exemplo: resolvido 14:00, fechado 16:00, para às 14:00. Sem hora de resolução, para às 16:00.

No SQL (tabela `#TerminalFARC`):

```sql
CASE
    WHEN b.resolve\_date IS NOT NULL                                  -- existe
     AND b.captura\_epoch IS NOT NULL
     AND b.resolve\_date >= b.captura\_epoch                          -- depois do começo
     AND (b.close\_date IS NULL OR b.resolve\_date <= b.close\_date)   -- não passa do fechamento
        THEN b.resolve\_date                                          -- para na resolução
    WHEN b.close\_date IS NOT NULL THEN b.close\_date                  -- senão, para no fechamento
    ELSE b.resolve\_date                                          -- rede de segurança; não roda (todo chamado aqui é fechado)
END AS terminal\_epoch
```

Sobre o `ELSE b.resolve\_date`, pense em três planos:

* **Plano A:** parar na resolução (quando ela faz sentido).
* **Plano B:** se não, parar no fechamento.
* **Plano C** (o `ELSE`): um reserva que nunca é usado.

Por que nunca é usado? O Plano C só entraria se o chamado não tivesse data de fechamento. Mas aqui só entram chamados **já fechados**, então sempre existe fechamento e o Plano B já dá conta. O `ELSE` fica só de reserva, para o cálculo nunca ficar sem resposta.

\---

## 5\. O que conta como "trabalhando"

Só contam dois status: "Em andamento" e "Aberto, aguarda atendimento" (a fila inicial). Qualquer outro pausa o cronômetro.

No SQL (tabela `#StatusEvA2B`, marcação do que é ativo):

```sql
CASE
    WHEN dest.destino = N'Em andamento'
      OR dest.destino = N'In Progress'
      OR dest.destino LIKE N'Aberto%aguarda%atendimento%'
        THEN 1 ELSE 0
END AS destino\_ativo
```

Sobre o `In Progress`: é só "Em andamento" em inglês. A consulta checa os dois nomes por garantia; como a base está em português, o que vale é "Em andamento".

Pegadinha: "Aberto, aguarda atendimento" (fila inicial) conta; "Aguarda atendimento" (espera depois do trabalho) não conta.

\---

## 6\. O chamado pode sair e voltar (reposse)

Cada período em que o chamado está com a A2B é uma "janela". A consulta soma todas as janelas, não só a última. Ela monta a linha do tempo de grupo e mantém só os trechos em que o grupo é A2B.

No SQL (tabela `#JanelasA2B`):

```sql
SELECT
    o.id,
    o.t AS win\_inicio\_epoch,
    CASE WHEN COALESCE(o.next\_t, tf.terminal\_epoch) > tf.terminal\_epoch
         THEN tf.terminal\_epoch ELSE COALESCE(o.next\_t, tf.terminal\_epoch) END AS win\_fim\_epoch
INTO #JanelasA2B
FROM ordered AS o
JOIN #TerminalFARC AS tf ON tf.id = o.id
WHERE o.is\_a2b = 1
  AND o.t < tf.terminal\_epoch;
```

\---

## 7\. Dois ajustes finos no tempo ativo

### 7.1. O "Em andamento" herdado não conta

Se o chamado chega na A2B já em "Em andamento" ligado por outro grupo, esse pedaço não conta. A A2B só conta o "Em andamento" que começou dentro da janela dela. A fila "Aberto, aguarda atendimento" é exceção e conta sempre.

### 7.2. O piso do Inicial

Quando o chamado é criado, o sistema registra quanto tempo levou a criação (o "Tempo Gasto" do evento de criação). O BO não conta esse tempinho inicial como atendimento. Então o cronômetro só começa depois dele.

Exemplo: chamado criado às 10:00, com 2 minutos registrados na criação. O cronômetro começa às 10:02, não às 10:00.

Isso só afeta chamados que nasceram na A2B. Para os que vieram de outro grupo, esse tempinho de criação aconteceu antes da A2B pegar o chamado, então não muda nada.

No SQL (tabela `#PisoInicial`):

```sql
b.open\_date + ISNULL(ig.init\_gasto\_seg, 0) AS piso\_inicial\_epoch
```

A soma aqui não soma tempo no resultado: ela calcula a **hora de largada**. `open\_date` é a hora da criação e `init\_gasto\_seg` é o tempo gasto nela; somando, chega-se ao ponto "criação + tempo da criação", que é a hora mínima em que o cronômetro pode começar. Como a largada fica mais tarde, o total acaba menor (o pedacinho inicial fica de fora).

É na tabela `#PecasAtivasA2B` que tudo se junta. Ela cruza duas coisas: os trechos em que o chamado estava **ativo** e as janelas em que ele estava **com a A2B**. Só sobra o que aparece nas duas ao mesmo tempo, e esses pedaços ("peças") são o que de fato conta. É aqui também que os dois ajustes acima entram: o piso da criação (a largada empurrada para frente) e a regra do herdado.

A regra do herdado, no código:

```sql
WHERE ov.fim\_ep > ov.ini\_ep
  AND (s.aberto\_fila = 1 OR s.ini >= j.win\_inicio\_epoch);
```

Lendo em português, linha por linha:

* `ov.fim\_ep > ov.ini\_ep`: só mantém pedaço que tem duração de verdade (o fim vem depois do começo).
* `s.aberto\_fila = 1`: se o trecho é a fila "Aberto, aguarda atendimento", conta sempre.
* `s.ini >= j.win\_inicio\_epoch`: se é "Em andamento", só conta se começou dentro da janela da A2B; se começou antes (herdado de outro grupo), fica de fora.

\---

## 8\. Corrida ou comercial (depende da gravidade)

P1 e P2 contam 24h por dia (corrida). P3, P4 e P5 contam só dia útil, das 08h às 20h (comercial), descontando também os feriados e pontos facultativos cadastrados na consulta.

No SQL (tabela `#TempoAtivoJanelasA2B`, soma das peças):

```sql
SUM(CASE
    WHEN sl.tipo\_resolucao = 'CORRIDA'
        THEN DATEDIFF(SECOND, p.inicio\_br, p.fim\_br)
    WHEN sl.tipo\_resolucao = 'COMERCIAL'
        THEN COALESCE(bh.segundos\_comerciais, 0)
    ELSE DATEDIFF(SECOND, p.inicio\_br, p.fim\_br)
END)
```

Lendo o `CASE`:

* **corrida** (P1/P2): conta o tempo cheio da peça, do começo ao fim (`DATEDIFF`).
* **comercial** (P3/P4/P5): usa o `segundos\_comerciais`, que é a peça recortada no horário comercial e no calendário válido (explicado abaixo).
* **`ELSE DATEDIFF(...)`**: rede de segurança. Se o chamado não tiver severidade definida (não cai em corrida nem em comercial), conta o tempo cheio, para não perder a peça. Na prática, com a severidade preenchida, esse caminho não é usado, igual ao `ELSE` do Terminal.

### Como o `segundos\_comerciais` é calculado

A ideia é simples: pegar a peça e ficar só com a parte que cai no horário comercial.

O SQL abaixo faz isso em cinco passos (numerados nos comentários). Logo depois do código, cada função e cada passo estão explicados com um exemplo.

```sql
SELECT segundos\_comerciais = COALESCE(SUM(x.segundos\_dia), 0)
FROM (
    SELECT segundos\_dia = CASE WHEN janela.fim\_calc > janela.ini\_calc
                THEN DATEDIFF(SECOND, janela.ini\_calc, janela.fim\_calc) ELSE 0 END
    FROM (
        -- 1) pega cada dia que a peça atravessa
        SELECT DATEADD(DAY, n.n, CAST(p.inicio\_br AS date)) AS dt
        FROM #Nums AS n
        WHERE n.n <= DATEDIFF(DAY, CAST(p.inicio\_br AS date), CAST(p.fim\_br AS date))
    ) AS dias
    CROSS APPLY (
        -- 2) a janela comercial daquele dia: das 08:00 às 20:00
        SELECT inicio\_janela = DATEADD(HOUR, 8,  CAST(dias.dt AS datetime2(0))),
               fim\_janela    = DATEADD(HOUR, 20, CAST(dias.dt AS datetime2(0)))
    ) AS h
    CROSS APPLY (
        -- 3) fica só com a parte da peça que cai dentro do 08:00-20:00
        SELECT ini\_calc = CASE WHEN p.inicio\_br > h.inicio\_janela THEN p.inicio\_br ELSE h.inicio\_janela END,
               fim\_calc = CASE WHEN p.fim\_br    < h.fim\_janela    THEN p.fim\_br    ELSE h.fim\_janela    END
    ) AS janela
    WHERE DATEDIFF(DAY, '19000101', dias.dt) % 7 BETWEEN 0 AND 4   -- 4) só segunda a sexta
      AND NOT EXISTS (SELECT 1 FROM #FeriadosFixos ff
                      WHERE ff.mes\_dia = RIGHT(CONVERT(char(10), dias.dt, 120), 5))
      AND NOT EXISTS (SELECT 1 FROM #FeriadosPorData fp             -- 5) pula feriados e facultativos
                      WHERE fp.data = CAST(dias.dt AS date))
) AS x
```

**Entendendo o bloco.** Ele faz uma coisa só: anda dia por dia e, em cada dia, guarda apenas o tempo da peça que cai no expediente (08:00 às 20:00, de segunda a sexta). No fim, soma tudo.

Veja com a peça de exemplo, de **quinta 18:00 até segunda 10:00**:

|Dia|É dia útil?|Parte que cai no 08:00-20:00|Conta|
|-|-|-|-|
|quinta|sim|18:00 às 20:00|2h|
|sexta|sim|08:00 às 20:00|12h|
|sábado|não|descartado|0|
|domingo|não|descartado|0|
|segunda|sim|08:00 às 10:00|2h|

Total: 2 + 12 + 2 = **16 horas**.

Se a sexta-feira desse exemplo estivesse cadastrada como feriado ou ponto facultativo, suas 12 horas seriam descartadas e o total seria **4 horas**.

Quatro pontos do código que costumam confundir:

* **Andar de dia em dia.** A peça pode cruzar vários dias, então o cálculo olha um dia de cada vez: quinta, depois sexta, depois sábado, e assim até o fim da peça. (A `#Nums` é só o truque que gera essa lista de dias.)
* **Aparar as pontas.** Em cada dia, conta só o que está dentro do expediente: o que vier antes das 08:00 ou depois das 20:00 é cortado. Ex.: num dia em que a peça só aparece a partir das 18:00, conta das 18:00 às 20:00; num dia em que ela cobre tudo, conta das 08:00 às 20:00. Se a peça não passa naquele dia, sobra zero.
* **Pular o fim de semana.** O código descobre o dia da semana com um truque: `01/01/1900` foi uma segunda; contando os dias desde lá e olhando o resto da divisão por 7, dá 0 a 4 para segunda a sexta, e 5 e 6 para sábado e domingo. Só os de segunda a sexta passam.
* **Pular feriados e pontos facultativos.** Mesmo que a data caia de segunda a sexta, ela não conta quando aparece em `#FeriadosFixos` ou `#FeriadosPorData`.

E as funções que aparecem, em uma linha cada:

* `CAST(... AS date)`: deixa só o dia (descarta a hora).
* `DATEADD`: soma dias a uma data, ou monta um horário sobre um dia (08:00, 20:00).
* `DATEDIFF`: mede a distância entre duas datas, em dias ou em segundos.
* `SUM` / `COALESCE(..., 0)`: soma os tempos; o `COALESCE` troca "vazio" por zero, quando não sobra nenhum dia.

### Onde o calendário é aplicado

O desconto de feriados e pontos facultativos é aplicado nos três caminhos que podem calcular tempo comercial:

* `#TempoAtivoJanelasA2B`, que soma as peças ativas nas janelas de posse;
* `#TempoAtendimentoRotina`, usado nas rotinas;
* `#TempoAtendimentoStatusLead`, usado no segundo cálculo dos chamados normais.

Os feriados fixos ficam em `#FeriadosFixos`, no formato `MM-DD`. Feriados móveis e pontos facultativos ficam em `#FeriadosPorData`, com a data completa. A tabela contém os pontos facultativos de 24 e 31/12/2025, necessários ao ciclo Dezembro/Janeiro, e as datas cadastradas de 2026.

O calendário afeta somente a contagem **comercial** de P3, P4 e P5. P1 e P2 continuam em tempo corrido e não descontam feriado.

\---

## 9\. Qual número vira o Tempo de Atendimento

Existem dois tipos de chamado, e cada tipo conta de um jeito:

* **Rotinas** (Passagem de turno, Job Summary Report): usam o intervalo da abertura até o fechamento. Para P1/P2, contam o intervalo corrido; para P3/P4/P5, ficam somente as horas comerciais dos dias válidos no calendário.
* **Todo o resto:** conta o **tempo ativo** — o tempo em que o chamado estava sendo trabalhado — só dentro das janelas em que esteve com a A2B.

Isso significa que existe um motor específico de rotina (`#TempoAtendimentoRotina`) e um caminho para os chamados normais. No caminho normal, a consulta compara os dois cálculos ativos descritos abaixo e fica com o maior.

As duas categorias reconhecidas pelo motor de rotina são:

```sql
WHEN b.categoria\_sym LIKE N'A2B.Realizar - Passagem de turno%'
  OR b.categoria\_sym LIKE N'A2B.Job Summary Report%'
    THEN N'ROTINA\_INTERVALO\_ABERTURA\_FECHAMENTO'
```

Quando a categoria começa com um desses dois nomes, `#MotorBase` escolhe `#TempoAtendimentoRotina`. As demais categorias seguem para o caminho dos chamados normais, calculado pelos períodos de status ativo.

Esse **tempo ativo** (o segundo tipo) é medido por **dois cálculos**, e a consulta fica com o **maior** dos dois. Os dois só contam o tempo dentro das janelas da A2B — **nenhum deles conta tempo de outro grupo**. A diferença entre eles aparece num caso: o chamado **chega na A2B já em "Em andamento"** — o status foi ligado antes, enquanto o chamado ainda estava com outro grupo. É nesse trecho que os dois divergem.

**Cálculo 1 — períodos ativos** (`#TempoAtivoJanelasA2B`)

Conta o "Em andamento" **mais a fila de espera** ("Aberto, aguarda atendimento"). Mas exige que o "Em andamento" tenha **começado dentro da janela da A2B**. Se o chamado já chega com o "Em andamento" ligado de antes, este cálculo descarta o trecho inteiro — inclusive a parte que já era da A2B.

> \*Exemplo:\* chamado em "Em andamento" desde 13:00 com outro grupo, entra na A2B às 14:00 e sai do status às 16:00. Como o "Em andamento" começou antes da A2B, o Cálculo 1 descarta tudo: \*\*0\*\*.

**Cálculo 2 — histórico de status** (`#TempoAtendimentoStatusLead`)

Conta **só o "Em andamento"**, sem a fila. Mas não faz essa exigência: conta o "Em andamento" a partir do momento em que a A2B assumiu o chamado. Assim, aproveita a parte que foi da A2B mesmo quando o status já vinha ligado de antes. (Continua sem contar o tempo do outro grupo: só conta o que caiu dentro da janela da A2B.)

> \*Exemplo:\* no mesmo caso, o Cálculo 2 conta das 14:00 (entrada na A2B) às 16:00: \*\*2h\*\*. A consulta fica com o maior dos dois, 2h.

No SQL, a escolha final (fora rotina) é o maior dos dois:

```sql
WHEN ISNULL(taj.tempo\_ativo\_janelas\_a2b\_seg, 0) > ISNULL(rb.tempo\_base\_seg, 0)
 AND ISNULL(taj.tempo\_ativo\_janelas\_a2b\_seg, 0) > 0
    THEN taj.tempo\_ativo\_janelas\_a2b\_seg   -- Cálculo 1 (períodos ativos)
ELSE rb.tempo\_base\_seg                      -- Cálculo 2 (histórico de status)
```

\---

## 10\. Do número para a coluna do relatório

O tempo em segundos vira `HH:MM:SS` no SELECT final.

```sql
CONCAT(
    CONVERT(varchar(20), f.tempo\_atendimento\_seg / 3600), N':',
    RIGHT(N'00' + CONVERT(varchar(2), (f.tempo\_atendimento\_seg % 3600) / 60), 2), N':',
    RIGHT(N'00' + CONVERT(varchar(2), f.tempo\_atendimento\_seg % 60), 2)
) AS \[Tempo de Atendimento]
```

Depois, o excedido é o Tempo de Atendimento menos a meta da severidade, e o `nHR\_FARC`/`FARC` saem dele:

```sql
CONVERT(decimal(18,2), f.atendimento\_excedido\_seg / 3600.0)              AS \[nHR\_FARC],
CONVERT(decimal(18,2), (f.atendimento\_excedido\_seg / 3600.0) \* 0.3)      AS \[FARC]
```

O `nHR\_FARC` é **proporcional**, com duas casas decimais: fração de hora não vira
hora inteira (5400 s = 1,50 h, e não 2 h). O fator 0,3 incide sobre o quociente
cheio (`excedente / 3600`).

> **Mudou em 2026-07-24.** Antes as duas colunas usavam
> `CEILING(CONVERT(decimal(18,6), ...) / 3600.0)`, que arredondava para cima.

\---

## 11\. Colinha

|Etapa|Tabela no SQL|O que faz|
|-|-|-|
|Entra na conta|`#EscopoIds`|fechado, período, A2B, tipo I/R/P, status terminal|
|Começo|`#InicioContagemA2B`|entrada na A2B; senão a abertura|
|Captura|`#CapturaStatus`|1ª ida para "Em andamento"|
|Terminal|`#TerminalFARC`|resolução se consistente; senão fechamento|
|Ativo|`#StatusEvA2B`|"Em andamento" e "Aberto, aguarda atendimento"|
|Janelas|`#JanelasA2B`|todos os períodos sob a A2B (reposse)|
|Piso/herdado|`#PisoInicial` / `#PecasAtivasA2B`|corta criação e "Em andamento" herdado|
|Feriados|`#FeriadosFixos` / `#FeriadosPorData`|exclui feriados e facultativos dos cálculos comerciais P3/P4/P5|
|Soma (interseção)|`#TempoAtivoJanelasA2B`|tempo ativo nas janelas A2B; corrida (P1/P2) ou comercial 08h-20h com calendário (P3/P4/P5)|
|Soma (por status)|`#StatusEventosLead`→`#IntervalosLead`→`#TempoAtendimentoStatusLead`|"Em andamento" por mudança de status, recortado nas janelas A2B e no calendário comercial|
|Resultado|`tempo\_atendimento\_seg`|rotina de Passagem de turno/Job Summary (abertura→fechamento) ou o maior entre os dois caminhos normais|

\---

## 12\. Observação sobre o BO

O cálculo foi feito para bater com o relatório BO e, na grande maioria dos chamados, bate. Em alguns casos de borda sobra uma diferença de poucos segundos até cerca de um minuto, porque o BO às vezes soma ou desconta pequenos tempos de forma própria, que não dá para reproduzir sem estragar os outros chamados. O esperado é bater na grande maioria, com tolerância nesses casos de borda.


---

## 13\. E a consulta do Power BI?

Além desta consulta, existe uma **consulta consolidada** feita para alimentar o painel:

```text
protect4/powerbi/consulta_faia_farc_power_bi.sql
```

O que muda entre as duas:

| | Esta consulta (`protect4/queries/`) | Consulta do painel (`protect4/powerbi/`) |
|---|---|---|
| O que retorna | só o FARC | FAIA **e** FARC, na mesma linha |
| Período | fixo, editado à mão nos parâmetros | dinâmico: os seis últimos ciclos completos |
| Para que serve | **referência técnica** do cálculo do FARC | fonte de dados do Power BI |
| Diagnósticos | tem, com `@MostrarDiagnostico = 1` | não tem: devolve um único resultado |

Pontos importantes:

- **esta consulta continua sendo a referência técnica do FARC.** A consolidada não a substitui;
- a consolidada **não reimplementa** o cálculo: ela reaproveita este mesmo motor (posse, reposse, terminal, rotinas, calendário) e o motor do FAIA, lado a lado;
- ela **não repete** as colunas que os dois indicadores têm em comum. Essas aparecem uma vez só;
- as colunas de cada indicador continuam separadas. **FAIA e FARC continuam sendo indicadores diferentes**;
- ela devolve **uma linha por chamado**.

A explicação das colunas do painel está em [powerbi-query.md](powerbi-query.md).
