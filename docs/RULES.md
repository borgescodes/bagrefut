# Regras do jogo (fundação)

## Constantes financeiras

- **Saldo máximo por clube**: R$ 100,00 (`clubs.balance_cents ≤ 10000`).
- **Saldo nunca negativo** (`clubs.balance_cents ≥ 0`).
- **Saldo inicial**: R$ 10,00 (1000 cents), creditado por `create_club` via `_credit_wallet`.
- **Ledger `wallet_transactions`** grava toda mutação — imutável para o usuário.

## Bandas de raridade e preço de referência (cents)

| Raridade | OVR   | Preço de referência  |
| -------- | ----- | -------------------- |
| peba     | 40-59 | R$ 0,50 - R$ 5,00    |
| paia     | 60-74 | R$ 5,01 - R$ 25,00   |
| pika     | 75-89 | R$ 25,01 - R$ 100,00 |

- A interpolação é linear dentro da raridade e do OVR.
- Depois da interpolação aplica-se multiplicador por posição:
  - GK: `0.90`
  - DEF: `0.95`
  - MID: `1.00`
  - ATA: `1.10`
- Depois do multiplicador: arredonda para cents, limita dentro da faixa da
  raridade e aplica teto global de R$ 100,00.
- Sistema compra a **50%** do preço de referência.
- Sistema vende a **100%** do preço de referência.
- Elenco deve ficar entre **5 e 15 cartas**. Venda ao sistema é bloqueada com
  5 cartas; compra do sistema é bloqueada com 15 cartas.

## Carta permanente e estoque do sistema

- `club_players` é a instância única e permanente da carta.
- `club_players.club_id IS NOT NULL`: carta pertence a um clube.
- `club_players.club_id IS NULL`: carta pertence ao sistema.
- `system_market_stock` lista explicitamente as cartas do sistema.
- A carta nunca é deletada/recriada em compra ou venda; a propriedade muda por
  `UPDATE club_players.club_id`.
- Todo jogador tem exatamente uma carta por `club_players.player_id UNIQUE`.

## Overall (`src/domain/calculators/overall.ts`)

Média ponderada por posição. Pesos somam 100:

- **GK**: goalkeeping 55, defending 15, physical 15, passing 10, velocity 5.
- **DEF**: defending 40, physical 25, velocity 15, passing 15, dribbling 5.
- **MID**: passing 30, dribbling 25, velocity 15, physical 15, defending 10, finishing 5.
- **ATA**: finishing 40, velocity 20, dribbling 20, physical 10, passing 10.

## Treino

- Um treino por clube por dia, usando o dia em `America/Belem`.
- Custos por sessão:
  - peba: 25 cents.
  - paia: 75 cents.
  - pika: 150 cents.
- Cada treino escolhe uma carta e um atributo.
- Progresso por carta/atributo fica em `club_player_attribute_progress`.
- Progressão: `0 -> 1 -> 2 -> 0`; ao completar 3 pontos, o atributo aumenta
  `+1` e OVR/preço são recalculados por trigger.
- O custo é cobrado mesmo quando o treino ainda não gera `+1`.
- Atributo máximo: 99.

## Multiplicador de improviso

- Posição natural = slot: **1.0**
- Adjacente (DEF↔MID, MID↔ATA): **0.85**
- Distante (DEF↔ATA): **0.70**
- Qualquer combinação envolvendo GK que não seja GK↔GK: **0.55**

## Estilo de jogo

| Estilo    | Ataque | Defesa |
| --------- | ------ | ------ |
| balanced  | 1.00   | 1.00   |
| offensive | 1.10   | 0.90   |
| defensive | 0.90   | 1.10   |

## Tabela de rodadas (6 clubes)

- 10 rodadas (5 turno + 5 returno), 3 partidas por rodada, 30 partidas totais.
- Cada clube joga exatamente 1 vez por rodada.
- Returno espelha o turno com casa/fora invertidos.
- Fixture list fixa e determinística em `src/domain/calculators/schedule.ts`.
- `season_start` usa a mesma fixture list no Postgres e so inicia com selecao
  persistida de exatamente 6 clubes elegiveis.

## Temporada e classificacao

- Estados operacionais expostos ao app: `waiting_for_clubs`, `ready_to_start`,
  `active`, `finished`.
- Enquanto houver menos de 6 clubes elegiveis, nenhuma temporada inicia e
  nenhuma rodada/partida parcial e criada.
- Se houver mais de 6 clubes elegiveis, o admin precisa escolher quais 6 entram;
  nao ha selecao aleatoria.
- Classificacao usa somente partidas `finished`: vitoria 3 pontos, empate 1,
  derrota 0.
- Desempate: pontos, vitorias, saldo de gols, gols pro, nome do clube e `club_id`
  como criterio deterministico final. Confronto direto nao foi implementado
  porque nao havia regra anterior definida.
- Premios finais sao valores inteiros em centavos, configurados por posicao e
  creditados uma unica vez como `season_prize` no ledger.

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

## Partidas e eventos

- Usuario approved pode ver placar/resumo de partidas da competicao.
- Eventos completos ficam disponiveis somente para admin approved ou usuario
  approved cujo clube seja mandante ou visitante da partida.
- Usuario approved estranho a partida nao ve `match_events`, mesmo depois de
  `reveal_at`, com data passada ou com partida `finished`.
- Pending, blocked e anon nao acessam resumo nem eventos.
- O resumo de partida nao inclui evento, descricao, minuto a minuto, jogador do
  evento, escalacao privada, tatica, seed ou payload de simulacao.
- O client nao insere, atualiza nem deleta `match_events`.
