# Documentação do cálculo FAIA: `tempo_primeiro_seg`, `DATEDIFF` e `COALESCE`

Esta documentação explica a parte do SQL que calcula o tempo de primeiro atendimento e as colunas derivadas do FAIA.

O foco é explicar o código de forma simples, mantendo os nomes técnicos originais das funções SQL. Assim, você consegue procurar a função no código e entender o que ela faz.

---

<a id="indice"></a>

## Índice

1. [Onde fica essa parte no código](#onde-fica-essa-parte-no-codigo)
2. [Resumo rápido da lógica](#resumo-rapido-da-logica)
3. [Código principal: `tempo_primeiro_seg`](#codigo-principal-tempo-primeiro-seg)
4. [Explicação linha por linha do `CASE`](#explicacao-linha-por-linha-do-case)
5. [`DATEDIFF(SECOND, ...)`](#datediff-second)
6. [`COALESCE(...)`](#coalesce)
7. [`bh.segundos_comerciais`](#bh-segundos-comerciais)
8. [Cálculo do `primeiro_excedido_seg`](#primeiro-excedido-seg)
9. [As 4 colunas calculadas no SELECT final](#quatro-colunas-calculadas)
10. [Glossário das funções e comandos usados](#glossario)
11. [Exemplos simples](#exemplos-simples)
12. [Resumo para consulta rápida](#resumo-para-consulta-rapida)
13. [E a consulta do Power BI?](#consulta-powerbi)

---

<a id="onde-fica-essa-parte-no-codigo"></a>

## 1. Onde fica essa parte no código

No arquivo SQL usado como base, o bloco principal de cálculo do FAIA está marcado com este comentário:

```sql
-- [9] Cálculo FAIA
```

As partes mais importantes são:

| Parte | Linhas (aprox.) | O que faz |
|---|---:|---|
| `tempo_primeiro_seg` | 537 a 545 | Calcula o tempo base do primeiro atendimento em segundos. |
| cálculo de `segundos_comerciais` (bloco `bh`) | 549 a 579 | Calcula o tempo dentro do horário comercial. |
| `primeiro_excedido_seg` | 584 a 588 | Calcula quanto passou da meta. |
| `[Tempo Primeiro Atendimento]` | 617 a 621 | Formata o tempo base em `HH:MM:SS`. |
| `[Primeiro Atendimento Excedido]` | 623 a 627 | Formata o excedente em `HH:MM:SS`. |
| `[nHR_FAIA]` | 639 a 641 | Transforma o excedente em horas proporcionais, com casas decimais. |
| `[FAIA]` | 643 a 645 | Calcula o valor final do FAIA. |

> Os números de linha são uma referência aproximada da versão atual do script e podem mudar quando ele é editado. As âncoras estáveis são o comentário `[9] Cálculo FAIA` e os nomes das colunas (`tempo_primeiro_seg`, `primeiro_excedido_seg`, etc.).

[Voltar ao índice](#indice)

---

<a id="resumo-rapido-da-logica"></a>

## 2. Resumo rápido da lógica

Tudo gira em torno de duas datas já calculadas em etapas anteriores: a **Data Abertura** (quando o chamado entrou na posse do grupo A2B) e a **Data Captura** (primeiro "Em andamento" depois disso).

A partir delas, o cálculo segue esta sequência:

```text
Data Abertura + Data Captura
        ↓
tempo_primeiro_seg      (tempo gasto, em segundos)
        ↓  compara com a meta da severidade
primeiro_excedido_seg   (quanto passou da meta, em segundos)
        ↓
Tempo Primeiro Atendimento / Primeiro Atendimento Excedido / nHR_FAIA / FAIA
```

Os dois valores do meio são **internos** (ficam em segundos) e não aparecem no resultado com esse nome. É o SELECT final que os transforma nas colunas visíveis, no formato `HH:MM:SS`.

Dois pontos guiam todo o cálculo:

1. **Como o tempo é contado depende da severidade.** O `tempo_primeiro_seg` é calculado de dois jeitos: contagem **corrida** (24x7) para P1 e P2, ou contagem **comercial** (só dias úteis, das 08:00 às 20:00) para P3, P4 e P5. Quem faz a parte comercial é o bloco `bh` (seção 7).
2. **O excedente é o tempo menos a meta.** O `primeiro_excedido_seg` pega o `tempo_primeiro_seg` e subtrai a meta de início da severidade. Se ficou dentro da meta, o excedente é zero. É desse excedente que saem o `nHR_FAIA` (horas proporcionais, com casas decimais) e o `FAIA` (`nHR_FAIA × 0,1`).

Em resumo: o tempo vira excedente, e o excedente vira o valor do FAIA.

[Voltar ao índice](#indice)

---

<a id="codigo-principal-tempo-primeiro-seg"></a>

## 3. Código principal: `tempo_primeiro_seg`

Trecho das linhas **539 a 547**:

```sql
CASE
    WHEN b.data_abertura_br IS NULL OR b.data_captura_br IS NULL THEN NULL
    WHEN b.data_captura_br < b.data_abertura_br THEN 0
    WHEN sl.tipo_inicio = 'CORRIDA'
        THEN DATEDIFF(SECOND, b.data_abertura_br, b.data_captura_br)
    WHEN sl.tipo_inicio = 'COMERCIAL'
        THEN COALESCE(bh.segundos_comerciais, 0)
    ELSE NULL
END AS tempo_primeiro_seg
```

Esse bloco cria a coluna interna:

```sql
tempo_primeiro_seg
```

Ela representa o **tempo de primeiro atendimento em segundos**.

A regra muda conforme o tipo de SLA:

| Tipo de SLA | O que o SQL faz |
|---|---|
| `CORRIDA` | Usa `DATEDIFF(SECOND, data_abertura, data_captura)`. |
| `COMERCIAL` | Usa `bh.segundos_comerciais`. |
| sem tipo válido | Retorna `NULL`. |

[Voltar ao índice](#indice)

---

<a id="explicacao-linha-por-linha-do-case"></a>

## 4. Explicação linha por linha do `CASE`

### Linha 539: `CASE`

```sql
CASE
```

Inicia uma regra condicional.

Pode ler como:

```text
se acontecer isso, faça aquilo; senão, teste a próxima condição.
```

O `CASE` executa a **primeira condição verdadeira**. Depois que uma condição bate, ele não continua testando as próximas.

---

### Linha 540: datas vazias

```sql
WHEN b.data_abertura_br IS NULL OR b.data_captura_br IS NULL THEN NULL
```

Se a Data Abertura ou a Data Captura estiver vazia, o SQL retorna `NULL`.

Isso evita calcular tempo com data faltando.

Em português:

```text
Se não tenho uma das duas datas, não tenho como calcular o tempo.
```

---

### Linha 541: captura antes da abertura

```sql
WHEN b.data_captura_br < b.data_abertura_br THEN 0
```

Se a Data Captura for menor que a Data Abertura, o SQL retorna `0`.

Isso é uma proteção contra dado estranho.

Em português:

```text
Se a captura apareceu antes da abertura, não calcula tempo negativo; considera zero.
```

---

### Linhas 542 a 543: SLA com contagem corrida

```sql
WHEN sl.tipo_inicio = 'CORRIDA'
    THEN DATEDIFF(SECOND, b.data_abertura_br, b.data_captura_br)
```

Se o tipo de contagem da severidade for `CORRIDA`, o SQL calcula a diferença direta entre as duas datas.

Nesse caso, ele não desconta sábado, domingo, feriado ou horário fora do expediente.

Ele mede o intervalo bruto entre:

```text
Data Abertura → Data Captura
```

---

### Linhas 544 a 545: SLA com contagem comercial

```sql
WHEN sl.tipo_inicio = 'COMERCIAL'
    THEN COALESCE(bh.segundos_comerciais, 0)
```

Se o tipo de contagem da severidade for `COMERCIAL`, ele usa o valor calculado antes em:

```sql
bh.segundos_comerciais
```

Esse valor vem do bloco `OUTER APPLY`, que calcula apenas o tempo dentro da janela comercial.

O `COALESCE` serve para isto:

```text
Se bh.segundos_comerciais vier vazio, use 0.
```

---

### Linha 546: nenhum caso anterior bateu

```sql
ELSE NULL
```

Se nenhuma condição anterior foi atendida, retorna `NULL`.

Isso acontece, por exemplo, se `sl.tipo_inicio` não for nem `CORRIDA` nem `COMERCIAL`.

---

### Linha 547: nome da coluna calculada

```sql
END AS tempo_primeiro_seg
```

Fecha o `CASE` e dá nome ao resultado.

Esse nome é:

```sql
tempo_primeiro_seg
```

Esse campo é usado depois para montar a coluna final:

```sql
[Tempo Primeiro Atendimento]
```

[Voltar ao índice](#indice)

---

<a id="datediff-second"></a>

## 5. `DATEDIFF(SECOND, ...)`

### O que é

`DATEDIFF` é uma função do SQL Server que calcula a diferença entre duas datas.

A estrutura é:

```sql
DATEDIFF(unidade, data_inicial, data_final)
```

No seu código aparece assim:

```sql
DATEDIFF(SECOND, b.data_abertura_br, b.data_captura_br)
```

Isso significa:

```text
calcule a diferença entre Data Abertura e Data Captura em segundos.
```

### O que significa `SECOND`

`SECOND` é a unidade usada no cálculo.

Então o resultado não vem em horas, nem em dias. Vem em **segundos**.

Exemplo:

```text
Data Abertura: 08:00:00
Data Captura: 08:15:30
```

Diferença:

```text
15 minutos e 30 segundos = 930 segundos
```

Então:

```sql
DATEDIFF(SECOND, '2026-01-01 08:00:00', '2026-01-01 08:15:30')
```

retorna:

```text
930
```

### Por que o SQL calcula em segundos

Porque depois fica mais fácil fazer conta:

```text
segundos ÷ 3600 = horas
segundos % 3600 = resto depois de tirar as horas
```

No SELECT final, o SQL pega esses segundos e monta o texto `HH:MM:SS`.

### Onde aparece no seu bloco

Na linha **543**:

```sql
DATEDIFF(SECOND, b.data_abertura_br, b.data_captura_br)
```

Usado para SLA `CORRIDA`.

Na linha **558**:

```sql
DATEDIFF(SECOND, janela.ini_calc, janela.fim_calc)
```

Usado para calcular os segundos dentro de uma janela comercial específica.

Na linha **567**:

```sql
DATEDIFF(DAY, CAST(b.data_abertura_br AS date), CAST(b.data_captura_br AS date))
```

Aqui a unidade muda para `DAY`, ou seja, diferença em dias. Esse trecho serve para saber quantos dias precisam ser percorridos no cálculo comercial.

[Voltar ao índice](#indice)

---

<a id="coalesce"></a>

## 6. `COALESCE(...)`

### O que é

`COALESCE` pega o primeiro valor que não está vazio.

A estrutura é:

```sql
COALESCE(valor1, valor2, valor3, ...)
```

Ele testa da esquerda para a direita.

Exemplo:

```sql
COALESCE(NULL, 0)
```

Resultado:

```text
0
```

Outro exemplo:

```sql
COALESCE(150, 0)
```

Resultado:

```text
150
```

Porque `150` não é nulo.

### Onde aparece no cálculo principal

Linha **545**:

```sql
COALESCE(bh.segundos_comerciais, 0)
```

Pode ler assim:

```text
Use bh.segundos_comerciais. Se ele estiver vazio, use 0.
```

### Por que isso existe

Se o cálculo comercial não encontrar nenhum segundo comercial, `bh.segundos_comerciais` pode ficar `NULL`.

Sem `COALESCE`, o resultado do tempo poderia ficar vazio.

Com `COALESCE`, a consulta transforma esse vazio em zero.

Isso evita que a coluna fique sem valor quando o correto é tratar como nenhum tempo comercial contado.

### Outro uso no bloco comercial

Linha **553**:

```sql
segundos_comerciais = COALESCE(SUM(x.segundos_dia), 0)
```

Pode ler assim:

```text
Some todos os segundos comerciais dos dias.
Se a soma vier vazia, use 0.
```

[Voltar ao índice](#indice)

---

<a id="bh-segundos-comerciais"></a>

## 7. `bh.segundos_comerciais` (a contagem do horário comercial)

`bh.segundos_comerciais` é o tempo de primeiro atendimento contado **apenas dentro do horário comercial**. Ele é usado quando a severidade tem contagem `COMERCIAL` (P3, P4 e P5).

O `bh` é o apelido do bloco `OUTER APPLY` que fica logo abaixo do `CASE` de `tempo_primeiro_seg`, dentro do bloco `[9] Cálculo FAIA`. O `OUTER APPLY` faz esse cálculo rodar uma vez para cada chamado da consulta principal.

### A ideia, em uma frase

> Em vez de medir o tempo direto entre abertura e captura, o SQL **quebra o período dia a dia** e, para cada dia útil, conta só o pedaço que cai entre **08:00 e 20:00**. No fim, soma os pedaços.

Assim, noite, madrugada, sábado e domingo não entram na conta.

### Código completo

```sql
OUTER APPLY (
    SELECT
        segundos_comerciais = COALESCE(SUM(x.segundos_dia), 0)
    FROM (
        SELECT
            segundos_dia = CASE
                WHEN janela.fim_calc > janela.ini_calc
                    THEN DATEDIFF(SECOND, janela.ini_calc, janela.fim_calc)
                ELSE 0
            END
        FROM (
            SELECT DATEADD(DAY, n.n, CAST(b.data_abertura_br AS date)) AS dt
            FROM #Nums AS n
            WHERE b.data_abertura_br IS NOT NULL
              AND b.data_captura_br IS NOT NULL
              AND b.data_captura_br >= b.data_abertura_br
              AND n.n <= DATEDIFF(DAY, CAST(b.data_abertura_br AS date), CAST(b.data_captura_br AS date))
        ) AS dias
        CROSS APPLY (
            SELECT
                inicio_janela = DATEADD(HOUR, 8,  CAST(dias.dt AS datetime2(0))),
                fim_janela    = DATEADD(HOUR, 20, CAST(dias.dt AS datetime2(0)))
        ) AS h
        CROSS APPLY (
            SELECT
                ini_calc = CASE WHEN b.data_abertura_br > h.inicio_janela THEN b.data_abertura_br ELSE h.inicio_janela END,
                fim_calc = CASE WHEN b.data_captura_br  < h.fim_janela    THEN b.data_captura_br  ELSE h.fim_janela    END
        ) AS janela
        WHERE DATEDIFF(DAY, '19000101', dias.dt) % 7 BETWEEN 0 AND 4
    ) AS x
) AS bh
```

### Lendo de dentro para fora

O bloco tem várias camadas. Fica mais fácil entender de dentro para fora:

| Apelido | O que representa | Como é montado |
|---|---|---|
| `dias` | A lista de dias do período, um por linha, do dia da abertura até o dia da captura. | `DATEADD(DAY, n.n, abertura)` usando os números da tabela `#Nums`. |
| `h` | A janela comercial cheia daquele dia: das **08:00** às **20:00**. | `inicio_janela = dia + 8h`, `fim_janela = dia + 20h`. |
| `janela` | A janela comercial **recortada** para caber no tempo real do chamado. | `ini_calc` = o maior entre abertura e 08:00; `fim_calc` = o menor entre captura e 20:00. |
| `segundos_dia` | Quantos segundos comerciais aquele dia contribui. | `DATEDIFF(SECOND, ini_calc, fim_calc)`, ou `0` se não sobrar intervalo. |
| `x` / `bh` | A soma dos `segundos_dia` de todos os dias úteis. | `SUM(segundos_dia)`, protegido por `COALESCE(..., 0)`. |

### Por que recortar a janela (`ini_calc` / `fim_calc`)

Cada dia tem a janela cheia 08:00–20:00, mas o chamado nem sempre ocupa o dia inteiro. O recorte garante que a conta não comece antes da abertura nem termine depois da captura.

- Abriu às 10:00? O dia começa a contar às **10:00**, não às 08:00.
- Capturou às 17:00? O dia para de contar às **17:00**, não às 20:00.
- Em um dia totalmente no meio do período (abertura antes, captura depois), conta a janela cheia: as 12 horas, das 08:00 às 20:00.

Quando o recorte não sobra nenhum intervalo (por exemplo, um dia em que o chamado só esteve aberto às 21:00), `fim_calc` não fica maior que `ini_calc`, e o `segundos_dia` daquele dia é `0`.

### Como o SQL sabe que é dia útil

```sql
WHERE DATEDIFF(DAY, '19000101', dias.dt) % 7 BETWEEN 0 AND 4
```

A data `1900-01-01` foi uma **segunda-feira**. Contando os dias a partir dela e tirando o resto da divisão por 7 (`% 7`), cada dia da semana vira um número fixo:

| Resto (`% 7`) | Dia da semana |
|---:|---|
| 0 | segunda |
| 1 | terça |
| 2 | quarta |
| 3 | quinta |
| 4 | sexta |
| 5 | sábado |
| 6 | domingo |

Como o filtro só deixa passar `BETWEEN 0 AND 4`, sábado (5) e domingo (6) ficam de fora.

### Exemplo passo a passo

Chamado com contagem `COMERCIAL`:

```text
Data Abertura: sexta-feira 18:00
Data Captura:  segunda-feira 10:00
```

O SQL monta um dia por linha e recorta cada janela:

| Dia | Janela cheia | Recorte (ini_calc → fim_calc) | Dia útil? | segundos_dia |
|---|---|---|---|---:|
| sexta | 08:00–20:00 | 18:00 → 20:00 | sim | 7200 (2h) |
| sábado | 08:00–20:00 | — | não | 0 |
| domingo | 08:00–20:00 | — | não | 0 |
| segunda | 08:00–20:00 | 08:00 → 10:00 | sim | 7200 (2h) |

Soma final:

```text
segundos_comerciais = 7200 + 0 + 0 + 7200 = 14400  (4 horas)
```

A diferença direta entre sexta 18:00 e segunda 10:00 seria bem maior, mas só as 4 horas comerciais entram no FAIA.

### Feriados e pontos facultativos

> **Correção (2026-07-29).** Esta seção afirmava que "não existe calendário de feriados na consulta". Isso **não é mais verdade** — e já não era desde 08/07/2026. O texto antigo ficou desatualizado em relação ao código.

A consulta **tem** calendário de feriados. Desde 2026-10-07 as datas não ficam
no SQL: vêm do arquivo de feriados (o calendário do TCU, o mesmo da Virtual TI e
da Decision), pelo parâmetro `@Feriados` ([feriados.txt](feriados.txt)). O bloco de feriados valida a
lista e monta duas tabelas:

| Tabela | Formato | Para que serve |
|---|---|---|
| `#FeriadosFixos` | `MM-DD` | feriados que caem sempre no mesmo dia todo ano (Natal, Tiradentes, 1º de Maio...) |
| `#FeriadosPorData` | `AAAA-MM-DD` | feriados móveis (Páscoa, Paixão de Cristo) e os pontos facultativos do TCU, que valem só no ano cadastrado |

No cálculo comercial, um dia que apareça em qualquer uma das duas **conta zero**, exatamente como sábado e domingo:

```sql
seg_comercial = CASE
    WHEN cal.eh_feriado_ou_facultativo = 1 THEN 0
    WHEN cal.eh_dia_util = 0              THEN 0
    ...
```

O calendário afeta **somente** a contagem comercial (P3, P4 e P5). P1 e P2 são corridos e não descontam feriado.

**Pendências reais do calendário:**

- os pontos facultativos de **2027** ainda não foram cadastrados no arquivo;
- até 2026-10-06 esta consulta não tinha `2025-12-24` e `2025-12-31`, presentes no FARC Protect4 e no painel. Com o arquivo de feriados, as três consultas leem a mesma lista e a diferença acabou: 4 rotinas abertas nesses dias (1666461, 1666507, 1667392, 1667408) passaram a ter `Tempo Primeiro Atendimento` 0:00:00, o mesmo valor do painel; nenhuma meta mudou. As duas datas estão na Portaria-TCU nº 10/2025;
- desde 2026-10-07 a lista é o calendário do TCU completo de 2025 (antes a A2B só tinha as datas a partir de 27/10/2025); os anos anteriores a 2025 só têm os feriados fixos.

[Voltar ao índice](#indice)

---

<a id="primeiro-excedido-seg"></a>

## 8. Cálculo do `primeiro_excedido_seg`

Depois de calcular `tempo_primeiro_seg`, o SQL calcula quanto passou da meta.

Trecho das linhas **586 a 590**:

```sql
CASE
    WHEN c.tempo_primeiro_seg IS NULL OR c.meta_inicio_seg IS NULL THEN NULL
    WHEN c.tempo_primeiro_seg > c.meta_inicio_seg THEN c.tempo_primeiro_seg - c.meta_inicio_seg
    ELSE 0
END AS primeiro_excedido_seg
```

### O que faz

| Situação | Resultado |
|---|---|
| tempo ou meta vazio | `NULL` |
| tempo maior que a meta | `tempo_primeiro_seg - meta_inicio_seg` |
| tempo dentro da meta | `0` |

### Tradução simples

```text
Se não tenho tempo ou não tenho meta, não calculo.
Se o tempo passou da meta, calculo quanto passou.
Se não passou da meta, o excedente é zero.
```

[Voltar ao índice](#indice)

---

<a id="quatro-colunas-calculadas"></a>

## 9. As 4 colunas calculadas no SELECT final

No SELECT final, existem 4 colunas principais relacionadas ao cálculo do FAIA.

Importante: algumas apenas formatam valores que já foram calculados antes.

---

### 9.1 `[Tempo Primeiro Atendimento]` — linhas 619 a 623

```sql
CASE WHEN f.tempo_primeiro_seg IS NULL THEN NULL ELSE CONCAT(
    CONVERT(varchar(20), f.tempo_primeiro_seg / 3600), N':',
    RIGHT(N'00' + CONVERT(varchar(2), (f.tempo_primeiro_seg % 3600) / 60), 2), N':',
    RIGHT(N'00' + CONVERT(varchar(2), f.tempo_primeiro_seg % 60), 2)
) END AS [Tempo Primeiro Atendimento]
```

Essa coluna pega `tempo_primeiro_seg` e mostra em formato de hora:

```text
HH:MM:SS
```

Ela não decide a regra de tempo. A regra já foi decidida antes em `tempo_primeiro_seg`.

---

### 9.2 `[Primeiro Atendimento Excedido]` — linhas 625 a 629

```sql
CASE WHEN f.primeiro_excedido_seg IS NULL THEN NULL ELSE CONCAT(
    CONVERT(varchar(20), f.primeiro_excedido_seg / 3600), N':',
    RIGHT(N'00' + CONVERT(varchar(2), (f.primeiro_excedido_seg % 3600) / 60), 2), N':',
    RIGHT(N'00' + CONVERT(varchar(2), f.primeiro_excedido_seg % 60), 2)
) END AS [Primeiro Atendimento Excedido]
```

Essa coluna pega `primeiro_excedido_seg` e também mostra em formato:

```text
HH:MM:SS
```

---

### 9.3 `[nHR_FAIA]` — linhas 641 a 643

```sql
CASE WHEN f.primeiro_excedido_seg IS NULL THEN NULL ELSE
    CONVERT(decimal(18, 2), f.primeiro_excedido_seg / 3600.0)
END AS [nHR_FAIA]
```

Essa coluna transforma segundos excedidos em horas.

O valor é **proporcional**, com duas casas decimais: uma fração de hora continua
sendo fração, não vira hora inteira. É o mesmo padrão do `nHR_FAIA` da Decision, que hoje fica no repositório
próprio da Decision.

Exemplo:

```text
1 segundo excedido    = 0,00 hora em nHR_FAIA
3601 segundos         = 1,00 hora em nHR_FAIA
5400 segundos (1h30)  = 1,50 hora em nHR_FAIA
```

> **Mudou em 2026-07-24.** Antes a coluna usava
> `CEILING(CONVERT(decimal(18,6), ...) / 3600.0)`, que arredondava para cima
> (1 segundo excedido virava 1 hora e 5400 s viravam 2 horas).

---

### 9.4 `[FAIA]` — linhas 645 a 647

```sql
CASE WHEN f.primeiro_excedido_seg IS NULL THEN NULL ELSE
    CONVERT(decimal(18, 2), (f.primeiro_excedido_seg / 3600.0) * 0.1)
END AS [FAIA]
```

Essa coluna calcula o valor final do FAIA.

Ela faz:

```text
FAIA = nHR_FAIA × 0,1
```

O fator 0,1 é aplicado sobre o quociente cheio (`excedente / 3600`), e não sobre
o `nHR_FAIA` já arredondado para 2 casas — mesma construção usada no FAIA da
Decision com o `fator_inicio`.

Exemplos:

```text
nHR_FAIA = 3,00  ->  FAIA = 3,00 × 0,1 = 0,30
nHR_FAIA = 1,50  ->  FAIA = 1,50 × 0,1 = 0,15
```

[Voltar ao índice](#indice)

---

<a id="glossario"></a>

## 10. Glossário das funções e comandos usados

| Função / comando | Explicação simples | Onde aparece |
|---|---|---:|
| `CASE` | Cria uma regra condicional: se acontecer X, retorna Y. | 539, 556, 586, 619, 625, 631, 641, 645 |
| `WHEN` | Condição dentro do `CASE`. | várias linhas |
| `THEN` | Resultado quando o `WHEN` é verdadeiro. | várias linhas |
| `ELSE` | Resultado padrão quando nenhum `WHEN` anterior bate. | várias linhas |
| `END AS nome` | Fecha o `CASE` e dá nome à coluna calculada. | 547, 590, 623, 629, 635, 643, 647 |
| `NULL` | Valor vazio, ausente ou não calculado. | várias linhas |
| `IS NULL` | Testa se o valor está vazio. | 540, 587, 619, 625, 632, 641, 645 |
| `DATEDIFF` | Calcula diferença entre duas datas. | 543, 558, 567, 579 |
| `SECOND` | Unidade em segundos para o `DATEDIFF`. | 543, 558 |
| `DAY` | Unidade em dias para o `DATEDIFF` ou `DATEADD`. | 562, 567, 579 |
| `COALESCE` | Retorna o primeiro valor não nulo. | 545, 553 |
| `OUTER APPLY` | Calcula uma informação auxiliar para cada linha da consulta principal. | 551 |
| `SUM` | Soma valores. | 553 |
| `DATEADD` | Soma tempo a uma data. | 562, 571, 572 |
| `CAST` | Converte um valor para outro tipo de dado. | 562, 567, 571, 572 |
| `CONVERT` | Converte valor para outro tipo de dado ou formato. | 620, 621, 622, 626, 627, 628, 642, 646 |
| `RIGHT` | Pega os últimos caracteres de um texto. | 621, 622, 627, 628 |
| `decimal(18, 2)` | Tipo numérico com 2 casas decimais, usado no `nHR_FAIA` e no `FAIA`. | 642, 646 |
| `%` | Operador de resto da divisão. | 579, 621, 622, 627, 628 |
| `AS` | Dá apelido/nome para coluna ou bloco. | várias linhas |

[Voltar ao índice](#indice)

---

<a id="exemplos-simples"></a>

## 11. Exemplos simples

### Exemplo 1: `CORRIDA`

Dados:

```text
Data Abertura: 01/01/2026 08:00:00
Data Captura:  01/01/2026 09:30:00
Tipo início:   CORRIDA
```

O SQL usa:

```sql
DATEDIFF(SECOND, b.data_abertura_br, b.data_captura_br)
```

Resultado:

```text
1 hora e 30 minutos = 5400 segundos
```

Então:

```text
tempo_primeiro_seg = 5400
```

---

### Exemplo 2: `COMERCIAL`

Dados:

```text
Data Abertura: sexta 19:00
Data Captura:  segunda 09:00
Tipo início:   COMERCIAL
```

O SQL não usa diferença direta entre sexta 19:00 e segunda 09:00.

Ele usa:

```sql
COALESCE(bh.segundos_comerciais, 0)
```

O `bh.segundos_comerciais` calcula apenas:

```text
sexta 19:00 às 20:00 = 1 hora
segunda 08:00 às 09:00 = 1 hora
```

Total:

```text
2 horas = 7200 segundos
```

Então:

```text
tempo_primeiro_seg = 7200
```

Sábado e domingo não entram nesse cálculo comercial.

---

### Exemplo 3: `COALESCE`

```sql
COALESCE(bh.segundos_comerciais, 0)
```

Se `bh.segundos_comerciais` for:

```text
7200
```

resultado:

```text
7200
```

Se `bh.segundos_comerciais` for:

```text
NULL
```

resultado:

```text
0
```

### Exemplos por severidade: semana × fim de semana

A diferença entre um chamado durante a semana e um no fim de semana depende do **tipo de contagem** da severidade:

- **Corrida (P1 e P2):** conta 24x7. Sábado e domingo valem igual a um dia útil, então o resultado no fim de semana é o mesmo que na semana.
- **Comercial (P3, P4 e P5):** conta só dia útil, das 08:00 às 20:00. O que cai no fim de semana é descartado, então um mesmo tempo real rende um FAIA menor (às vezes zero) quando acontece no sábado ou domingo.

Em todos os exemplos: `Excedente = tempo − meta` (nunca negativo), `nHR_FAIA` converte o excedente em horas proporcionais com 2 casas decimais (`excedente / 3600`) e `FAIA = nHR_FAIA × 0,1`.

#### P1 — corrida, meta 15 min (900 s)

| Caso | Abertura → Captura | tempo_primeiro_seg | Excedente | nHR_FAIA | FAIA |
|---|---|---:|---:|---:|---:|
| Semana | terça 10:00 → terça 11:15 | 4500 s (1h15) | 3600 s (1h) | 1 | 0,10 |
| Fim de semana | sábado 10:00 → sábado 11:15 | 4500 s (1h15) | 3600 s (1h) | 1 | 0,10 |

O sábado conta igual. Se a contagem fosse comercial, esse sábado renderia 0; como P1 é 24x7, conta os 4500 s normalmente.

#### P2 — corrida, meta 60 min (3600 s)

| Caso | Abertura → Captura | tempo_primeiro_seg | Excedente | nHR_FAIA | FAIA |
|---|---|---:|---:|---:|---:|
| Semana | quarta 09:00 → quarta 11:30 | 9000 s (2h30) | 5400 s (1h30) | 1,50 | 0,15 |
| Fim de semana | domingo 09:00 → domingo 11:30 | 9000 s (2h30) | 5400 s (1h30) | 1,50 | 0,15 |

Domingo também conta integralmente; o resultado é o mesmo da semana.

#### P3 — comercial, meta 4 h (14400 s)

| Caso | Abertura → Captura | tempo_primeiro_seg | Excedente | nHR_FAIA | FAIA |
|---|---|---:|---:|---:|---:|
| Semana | terça 09:00 → terça 15:00 | 21600 s (6h) | 7200 s (2h) | 2 | 0,20 |
| Fim de semana | sábado 09:00 → sábado 18:00 | 0 s | 0 s | 0 | 0,00 |

No sábado não há horário comercial, então o tempo é zero. Mesmo levando 9 horas reais, o chamado fica dentro da meta e "Atende".

#### P4 — comercial, meta 4 h (14400 s)

| Caso | Abertura → Captura | tempo_primeiro_seg | Excedente | nHR_FAIA | FAIA |
|---|---|---:|---:|---:|---:|
| Semana | quinta 17:00 → sexta 12:00 | 25200 s (7h) | 10800 s (3h) | 3 | 0,30 |
| Fim de semana | sábado 10:00 → segunda 11:00 | 10800 s (3h) | 0 s | 0 | 0,00 |

Na semana, a noite entre quinta e sexta (20:00 às 08:00) é descartada; sobram 3h na quinta e 4h na sexta. No fim de semana, sábado e domingo não contam; sobram só as 3h de segunda (08:00 às 11:00), que ficam dentro da meta.

#### P5 — comercial, meta 12 h (43200 s)

| Caso | Abertura → Captura | tempo_primeiro_seg | Excedente | nHR_FAIA | FAIA |
|---|---|---:|---:|---:|---:|
| Semana | segunda 09:00 → terça 17:00 | 72000 s (20h) | 28800 s (8h) | 8 | 0,80 |
| Fim de semana | sábado 09:00 → terça 12:00 | 57600 s (16h) | 14400 s (4h) | 4 | 0,40 |

Na semana, conta 11h na segunda (09:00 às 20:00) e 9h na terça (08:00 às 17:00). No fim de semana, sábado e domingo somam zero; conta 12h na segunda e 4h na terça, totalizando 16h.

[Voltar ao índice](#indice)

---

<a id="resumo-para-consulta-rapida"></a>

## 12. Resumo para consulta rápida

| Item | Explicação curta |
|---|---|
| `tempo_primeiro_seg` | Tempo base do primeiro atendimento, em segundos. |
| `DATEDIFF(SECOND, abertura, captura)` | Diferença direta entre abertura e captura, em segundos. |
| `COALESCE(bh.segundos_comerciais, 0)` | Usa o tempo comercial calculado; se vier vazio, usa zero. |
| `bh.segundos_comerciais` | Tempo contado somente dentro da janela comercial. |
| `primeiro_excedido_seg` | Quanto o tempo base passou da meta. |
| `[Tempo Primeiro Atendimento]` | `tempo_primeiro_seg` formatado como `HH:MM:SS`. |
| `[Primeiro Atendimento Excedido]` | `primeiro_excedido_seg` formatado como `HH:MM:SS`. |
| `[nHR_FAIA]` | Excedente convertido para horas proporcionais, com 2 casas decimais. |
| `[FAIA]` | `nHR_FAIA × 0,1`. |

[Voltar ao índice](#indice)

---

<a id="consulta-powerbi"></a>

## 13. E a consulta do Power BI?

Além desta consulta, existe uma **consulta consolidada** feita para alimentar o painel:

```text
queries/consulta_faia_farc_painel.sql   (executada pela consulta do Power BI, powerbi/consulta_faia_farc_power_bi.m)
```

O que muda entre as duas:

| | Esta consulta (`queries/`) | Consulta do painel (`powerbi/`) |
|---|---|---|
| O que retorna | só o FAIA | FAIA **e** FARC, na mesma linha |
| Período | fixo, editado à mão nos parâmetros | dinâmico: os últimos `@PBI_QuantidadeCiclos` ciclos completos, do dia 24 ao final do dia 23 do mês seguinte (padrão 12) |
| Para que serve | **referência técnica** do cálculo do FAIA | fonte de dados do Power BI |
| Diagnósticos | tem, com `@MostrarDiagnostico = 1` | não tem: devolve um único resultado |

Pontos importantes:

- **esta consulta continua sendo a referência técnica do FAIA.** A consolidada não a substitui;
- a consolidada **não reimplementa** o cálculo: ela reaproveita este mesmo motor de primeiro atendimento e o motor do FARC, lado a lado;
- ela **não repete** as colunas que os dois indicadores têm em comum (SDM, tipo, severidade, categoria, responsáveis, datas do chamado). Essas aparecem uma vez só;
- as colunas de cada indicador continuam separadas: o FAIA tem as suas, o FARC tem as suas. **FAIA e FARC continuam sendo indicadores diferentes** e nenhum passou a usar regra do outro;
- ela devolve **uma linha por chamado**.

A explicação das colunas do painel está em [powerbi-query.md](../powerbi/powerbi-query.md).

[Voltar ao índice](#indice)
