# Regras do jogo (fundação)

## Constantes financeiras

- **Saldo máximo por clube**: R$ 999,99 (`clubs.balance_cents ≤ 99999`).
- **Saldo nunca negativo** (`clubs.balance_cents ≥ 0`).
- **Saldo inicial**: R$ 10,00 (1000 cents), creditado por `create_club` via `_credit_wallet`.
- **Preço máximo por carta/anúncio/oferta**: R$ 100,00 (10.000 cents).
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
- Elenco deve ficar entre **5 e 10 cartas**. Venda é bloqueada com 5; compra é
  bloqueada com 10.

## Carta permanente e mercado fechado

- Existem 60 jogadores únicos para seis clubes.
- Cada clube recebe 10 cartas no pacote inicial.
- `club_players` é a instância única e permanente da carta.
- `club_players.club_id IS NOT NULL`: carta pertence a um clube.
- `club_players.club_id IS NULL`: carta pertence ao sistema.
- `system_market_stock.is_market_eligible = false`: pool exclusivo dos pacotes.
- `system_market_stock.is_market_eligible = true`: carta vendida por clube e disponível
  na vitrine do sistema.
- Vitrine comercial começa vazia.
- Carta nunca é deletada/recriada em compra ou venda; propriedade muda por
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
- Cada treino escolhe uma carta própria e um atributo.
- Progresso por carta/atributo fica em `club_player_attribute_progress`.
- Progressão: `0 -> 1 -> 2 -> 0`; ao completar 3 pontos, atributo aumenta `+1`
  e OVR/preço são recalculados por trigger.
- Custo é cobrado mesmo quando treino ainda não gera `+1`.
- Atributo máximo: 99.

## Mercado P2P e ofertas

- Anúncios aceitam preço entre 1 e 10.000 cents e expõem somente status `open`.
- Criar anúncio reserva carta própria; cancelar libera; comprar transfere a carta
  permanente por `UPDATE club_players.club_id`.
- Compra P2P debita comprador como `market_purchase` e credita vendedor como
  `market_sale`, ambos referenciando mesmo `market_listings.id`.
- Oferta aceita no máximo 5 cartas por lado.
- `cash_cents` é pago por `from_club` para `to_club` e usa `transfer_cash` no
  ledger dos dois clubes.
- Anúncios e ofertas preservam elencos entre 5 e 10 cartas.
- Saldo permanece entre 0 e 99.999 cents.
- Dinheiro por anúncio/oferta permanece entre 0 e 10.000 cents.
- Cartas em anúncio ou oferta pendente usam `is_reserved = true` e não podem ser
  vendidas, treinadas, escaladas nem reutilizadas.
- Aceite transfere todas cartas e dinheiro atomicamente.
- Aceite, rejeição e cancelamento são idempotentes para respectivo estado final.
- Ofertas vencidas mudam para `expired` e liberam cartas.
- Locks de anúncio/oferta, clubes e cartas, com ordem UUID estável, impedem saldo,
  ledger ou propriedade duplicados.
- Contrato completo: `docs/MARKET.md`.

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
- Returno espelha turno com casa/fora invertidos.
- Fixture list fixa e determinística em `src/domain/calculators/schedule.ts`.
- `season_start` usa mesma fixture list no Postgres e só inicia com seleção
  persistida de exatamente 6 clubes elegíveis.

## Temporada e classificação

- Estados operacionais expostos ao app: `waiting_for_clubs`, `ready_to_start`,
  `active`, `finished`.
- Enquanto houver menos de 6 clubes elegíveis, nenhuma temporada inicia e
  nenhuma rodada/partida parcial é criada.
- Se houver mais de 6 clubes elegíveis, admin escolhe quais 6 entram.
- Classificação usa somente partidas `finished`: vitória 3 pontos, empate 1,
  derrota 0.
- Desempate: pontos, vitórias, saldo de gols, gols pró, nome do clube e `club_id`
  como critério determinístico final.
- Prêmios finais são valores inteiros em centavos, configurados por posição e
  creditados uma única vez como `season_prize`.

## Janela diária (América/Belém)

- **21:55**: fechamento automático de escalações (`rounds.lineup_lock_at`).
- **22:00**: início da rodada (`rounds.starts_at`).
- **22:10**: rodada finalizada (`rounds.ends_at`).
- Processador usa timestamps persistidos em cada rodada.
- `rounds.lineups_locked_at`, `rounds.simulation_started_at` e
  `rounds.finalized_at` registram execução operacional.

## Setores (19 únicos)

`centro`, `cidade_nova`, `promissao`, `jaderlandia`, `uraim`, `jardim`,
`flamboyant`, `angelim`, `camboata`, `buriti`, `laercio`, `bela_vista`,
`nagibao`, `ipixuna`, `caipe`, `paulo_sexto`, `morada_do_sol`,
`morada_do_vento`, `nova_conquista`.

## Formações

`1-2-1-1`, `1-1-2-1`, `1-1-1-2`, `0-2-2-1` (fut 5, com GK + 4 de linha).

## Partidas e eventos

- Usuário approved pode ver placar/resumo de partidas da competição.
- Eventos completos ficam disponíveis somente para admin approved ou usuário
  approved cujo clube seja mandante ou visitante.
- Usuário estranho à partida não vê `match_events`.
- Pending, blocked e anon não acessam resumo nem eventos.
- Resumo não inclui evento, descrição, minuto a minuto, jogador do evento,
  escalação privada, tática, seed ou payload.
- Client não insere, atualiza nem deleta `match_events`.

## Simulador determinístico de partidas

- Versão atual: `SIMULATION_VERSION = 1`.
- Seed persistida: `season_id:round_id:match_id:simulation_version`.
- Motor TypeScript puro usa PRNG determinístico; RPC SQL usa
  `md5(seed:contador)` sem `random()`.
- Escalação manual válida salva antes de `rounds.lineup_lock_at` tem prioridade.
- Sem escalação válida, simulação gera escalação automática.
- Escalação automática usa cartas elegíveis do clube, sem repetição, priorizando
  posição natural, menor penalidade, maior OVR efetivo, maior OVR base e ID estável.
- Fallback usa `1-2-1-1` e `balanced`.
- Snapshot histórico fica em `match_lineup_snapshots`.
- Forças são limitadas a `0..100`: ataque, defesa, goleiro e geral.
- Eventos: `match_started`, `chance`, `shot`, `save`, `goal`, `halftime`,
  `match_finished`.
- Estatísticas por clube ficam em `match_statistics`.
- Prêmios de partida: vitória `75`, empate `25`, derrota `0` cents.
- `simulate_match` e `simulate_round` são RPCs admin-only e idempotentes.
- Cron chama `process_due_rounds(now())` com service role.
- Última rodada finalizada encerra temporada quando existem 10 rodadas e
  30 partidas `finished`.
