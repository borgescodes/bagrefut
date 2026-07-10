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

## Mercado P2P e ofertas

- Anúncios aceitam preço entre 1 e 10.000 cents e expõem somente status `open`
  na listagem pública.
- Criar anúncio reserva a carta na mesma transação; cancelar libera a reserva;
  comprar transfere a carta permanente por `UPDATE club_players.club_id`.
- Compra P2P debita o comprador como `market_purchase` e credita o vendedor como
  `market_sale`, ambos referenciando o mesmo `market_listings.id`.
- Oferta aceita no máximo 5 cartas por lado. `cash_cents` é pago por `from_club`
  para `to_club` e usa `transfer_cash` no ledger dos dois clubes.
- Anúncios e ofertas preservam elencos entre 5 e 15 cartas e saldo entre 0 e
  10.000 cents.
- Cartas em anúncio ou oferta pendente usam `is_reserved = true` e não podem ser
  vendidas, treinadas, escaladas nem reutilizadas em outra negociação.
- Aceite transfere todas as cartas e o dinheiro atomicamente; falha não deixa
  transferência parcial.
- Aceite, rejeição e cancelamento são idempotentes para o respectivo estado
  final. Ofertas vencidas mudam para `expired` e liberam as cartas.
- Locks de anúncio/oferta, clubes e cartas, com ordem UUID estável, impedem saldo,
  ledger ou propriedade duplicados em concorrência.
- Contrato completo: `docs/MARKET.md`.

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
- **22:10**: rodada finalizada (`rounds.ends_at`).
- O processador usa os timestamps persistidos em cada rodada. Nao ha horario
  hardcoded no cron; atraso do servidor executa etapas vencidas em ordem.
- `rounds.lineups_locked_at`, `rounds.simulation_started_at` e
  `rounds.finalized_at` registram a execucao operacional de cada etapa.

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

## Simulador deterministico de partidas

- Versao atual: `SIMULATION_VERSION = 1`.
- Seed persistida por partida: `season_id:round_id:match_id:simulation_version`.
- O motor TypeScript puro usa PRNG deterministico derivado da seed; a RPC SQL usa
  `md5(seed:contador)` para gerar rolagens deterministicas sem `random()`.
- Escalacao manual valida e salva antes de `rounds.lineup_lock_at` tem prioridade.
  Quando ausente ou invalida, a simulacao gera escalacao automatica.
- Escalacao automatica usa somente cartas elegiveis do clube, sem repeticao, na
  ordem: posicao natural do slot, menor penalidade de improviso, maior OVR
  efetivo, maior OVR base, identificador estavel.
- Fallback automatico usa `1-2-1-1` e `balanced`.
- Snapshot historico fica em `match_lineup_snapshots` com origem
  `manual`/`automatic`, formacao, estilo, posicao natural, posicao usada, OVR
  base, OVR efetivo, penalidade e atributos.
- Forcas sao limitadas a `0..100`: ataque, defesa, goleiro e geral.
- Modificadores de formacao:
  - `1-2-1-1`: ataque `0.98`, defesa `1.08`, chances `0.96`, exposicao `0.88`.
  - `1-1-2-1`: ataque `1.02`, defesa `0.99`, chances `1.08`, exposicao `1.00`.
  - `1-1-1-2`: ataque `1.10`, defesa `0.92`, chances `1.06`, exposicao `1.12`.
  - `0-2-2-1`: ataque `1.05`, defesa `0.94`, chances `1.10`, exposicao `1.20`.
- Estilos reutilizam o contrato atual: `balanced` neutro, `offensive` ataque
  `1.10` e defesa `0.90`, `defensive` ataque `0.90` e defesa `1.10`.
- Eventos gravados: `match_started`, `chance`, `shot`, `save`, `goal`,
  `halftime`, `match_finished`. Placar final vem dos eventos de gol.
- Estatisticas por clube ficam em `match_statistics`: posse, chances,
  finalizacoes, finalizacoes no alvo, defesas e gols.
- Premios de partida usam `match_reward_config`: vitoria `75`, empate `25`,
  derrota `0` cents por padrao. Credito passa por `_credit_wallet`; premios
  zero tambem geram ledger.
- `simulate_match` e `simulate_round` sao RPCs admin-only e idempotentes para
  operacao manual. O cron chama `process_due_rounds(now())` com service role.
- Em `starts_at`, a rodada simula partidas e credita `match_reward`, mas nao
  marca `rounds.is_processed`.
- Em `ends_at`, `round_finalize` exige exatamente 3 partidas `finished`, marca
  `rounds.is_processed = true` e preenche `rounds.finalized_at`.
- A ultima rodada finalizada dispara encerramento da temporada quando existem
  10 rodadas e 30 partidas `finished`; `season_prize` continua sendo creditado
  uma unica vez por clube.
- Teste estatistico TypeScript roda 2.000 seeds fixas por cenario. Faixas:
  times iguais com diferenca de vitorias menor que `8%`, time superior vence
  entre `50%` e `90%`, empates acima de `8%`, media de gols entre `1.8` e `4.8`,
  placares com 8+ gols abaixo de `4%`. As faixas cobrem variancia fixa sem
  permitir vitoria garantida.
