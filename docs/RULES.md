# Regras do jogo (fundação)

## Constantes financeiras

- **Saldo máximo por clube**: R$ 100,00 (`clubs.balance_cents ≤ 10000`).
- **Saldo nunca negativo** (`clubs.balance_cents ≥ 0`).
- **Saldo inicial**: R$ 10,00 (1000 cents), creditado por `create_club` via `_credit_wallet`.
- **Ledger `wallet_transactions`** grava toda mutação — imutável para o usuário.

## Bandas de raridade e preço de referência (cents)

| Raridade | OVR   | Preço de referência |
| -------- | ----- | ------------------- |
| peba     | 40-59 | R$ 0,50 - R$ 5,00   |
| paia     | 60-74 | R$ 5,01 - R$ 25,00  |
| pika     | 75-89 | R$ 25,01 - R$ 100,00 |

- Sistema compra a **50%** do preço de referência.
- Sistema vende a **100%** do preço de referência.

## Overall (`src/domain/calculators/overall.ts`)

Média ponderada por posição. Pesos somam 100:

- **GK**: goalkeeping 55, defending 15, physical 15, passing 10, velocity 5.
- **DEF**: defending 40, physical 25, velocity 15, passing 15, dribbling 5.
- **MID**: passing 30, dribbling 25, velocity 15, physical 15, defending 10, finishing 5.
- **ATA**: finishing 40, velocity 20, dribbling 20, physical 10, passing 10.

## Multiplicador de improviso

- Posição natural = slot: **1.0**
- Adjacente (DEF↔MID, MID↔ATA): **0.85**
- Distante (DEF↔ATA): **0.70**
- Qualquer combinação envolvendo GK que não seja GK↔GK: **0.55**

## Estilo de jogo

| Estilo     | Ataque | Defesa |
| ---------- | ------ | ------ |
| balanced   | 1.00   | 1.00   |
| offensive  | 1.10   | 0.90   |
| defensive  | 0.90   | 1.10   |

## Tabela de rodadas (6 clubes)

- 10 rodadas (5 turno + 5 returno), 3 partidas por rodada, 30 partidas totais.
- Cada clube joga exatamente 1 vez por rodada.
- Returno espelha o turno com casa/fora invertidos.
- Fixture list fixa e determinística em `src/domain/calculators/schedule.ts`.

## Janela diária (América/Belém)

- **21:55**: fechamento automático de escalações (`rounds.lineup_lock_at`).
- **22:00**: início da rodada (`rounds.starts_at`).
- **22:10**: rodada finalizada (`rounds.ends_at`), prêmios creditados.

## Setores (19 únicos)

`centro`, `cidade_nova`, `promissao`, `jaderlandia`, `uraim`, `jardim`,
`flamboyant`, `angelim`, `camboata`, `buriti`, `laercio`, `bela_vista`,
`nagibao`, `ipixuna`, `caipe`, `paulo_sexto`, `morada_do_sol`,
`morada_do_vento`, `nova_conquista`.

## Formações

`1-2-1-1`, `1-1-2-1`, `1-1-1-2`, `0-2-2-1` (fut 5, com GK + 4 de linha).
