# Regras do jogo (fundação)

## Constantes financeiras

- **Saldo máximo por clube**: R$ 999,99 (`clubs.balance_cents ≤ 99999`).
- **Saldo nunca negativo** (`clubs.balance_cents ≥ 0`).
- **Saldo inicial**: R$ 10,00 (1000 cents), creditado por `create_club` via `_credit_wallet`.
- **Preço máximo por carta/anúncio/oferta**: R$ 100,00 (10.000 cents).
- **Ledger `wallet_transactions`** grava toda mutação - imutável para usuário.

## Bandas de raridade e preço de referência (cents)

| Raridade | OVR   | Preço de referência  |
| -------- | ----- | -------------------- |
| peba     | 40-59 | R$ 0,50 - R$ 5,00    |
| paia     | 60-74 | R$ 5,01 - R$ 25,00   |
| pika     | 75-89 | R$ 25,01 - R$ 100,00 |

- Interpolação é linear dentro da raridade e OVR.
- Depois da interpolação aplica-se multiplicador por posição:
  - GK: `0.90`
  - DEF: `0.95`
  - MID: `1.00`
  - ATA: `1.10`
- Depois do multiplicador: arredonda para cents, limita dentro da faixa da
  raridade e aplica teto global de R$ 100,00.
- Sistema compra a **50%** do preço de referência.
- Sistema vende a **100%** do preço de referência.
- Elenco deve ficar entre **5 e 10 cartas**. Venda ao sistema é bloqueada com
  5 cartas; compra do sistema é bloqueada com 10 cartas.

## Carta permanente e estoque do sistema

- `club_players` é instância única e permanente da carta.
- `club_players.club_id IS NOT NULL`: carta pertence a clube.
- `club_players.club_id IS NULL`: carta pertence ao sistema.
- `system_market_stock.is_market_eligible = false`: carta reservada ao pool dos pacotes iniciais.
- `system_market_stock.is_market_eligible = true`: carta vendida por clube e disponível na vitrine.
- Vitrine comercial começa vazia; estoque nasce das vendas dos clubes.
- Carta nunca é deletada/recriada em compra ou venda; propriedade muda por
  `UPDATE club_players.club_id`.
- Todo jogador tem exatamente uma carta por `club_players.player_id UNIQUE`.

## Pacotes iniciais balanceados

- Existem exatamente 6 pacotes de produção: `PACK01` a `PACK06`.
- Cada pacote contém 10 cartas: 2 GK, 3 DEF, 3 MID e 2 ATA.
- Cada jogador aparece em exatamente um pacote.
- OVR total por pacote fica em 578 ou 579, conforme template persistido.
- Cada clube recebe aleatoriamente um template ainda livre.
- `initial_packs.starter_pack_template_id UNIQUE` impede repetição entre clubes.
- `create_club` reserva template, cria clube, credita saldo e cria pacote na
  mesma transação.
- `open_initial_pack` entrega exatamente cartas do template associado.
- Carta com `is_market_eligible = true` nunca entra no pacote.
- Reabrir pacote retorna mesmos itens sem duplicar posse ou registros.
- Falha em qualquer carta reverte abertura completa.

## Overall (`src/domain/calculators/overall.ts`)

Média ponderada por posição. Pesos somam 100:

- **GK**: goalkeeping 55, defending 15, physical 15, passing 10, velocity 5.
- **DEF**: defending 40, physical 25, velocity 15, passing 15, dribbling 5.
- **MID**: passing 30, dribbling 25, velocity 15, physical 15, defending 10, finishing 5.
- **ATA**: finishing 40, velocity 20, dribbling 20, physical 10, passing 10.

## Treino

- Um treino por clube por dia, usando dia em `America/Belem`.
- Custos por sessão:
  - peba: 25 cents.
  - paia: 75 cents.
  - pika: 150 cents.
- Cada treino escolhe carta e atributo.
- Progresso por carta/atributo fica em `club_player_attribute_progress`.
- Progressão: `0 -> 1 -> 2 -> 0`; ao completar 3 pontos, atributo aumenta
  `+1` e OVR/preço são recalculados por trigger.
- Custo é cobrado mesmo quando treino ainda não gera `+1`.
- Atributo máximo: 99.

## Mercado P2P e ofertas

- Anúncios aceitam preço entre 1 e 10.000 cents e expõem somente status `open`
  na listagem pública.
- Criar anúncio reserva carta na mesma transação; cancelar libera reserva;
  comprar transfere carta permanente por `UPDATE club_players.club_id`.
- Compra P2P debita comprador como `market_purchase` e credita vendedor como
  `market_sale`, ambos referenciando mesmo `market_listings.id`.
- Oferta aceita no máximo 5 cartas por lado. `cash_cents` é pago por `from_club`
  para `to_club` e usa `transfer_cash` no ledger dos dois clubes.
- Anúncios e ofertas preservam elencos entre 5 e 10 cartas e saldo entre 0 e
  99.999 cents; preço/dinheiro por operação permanece limitado a 10.000 cents.
- Cartas em anúncio ou oferta pendente usam `is_reserved = true` e não podem ser
  vendidas, treinadas, escaladas nem reutilizadas em outra negociação.
- Aceite transfere todas cartas e dinheiro atomicamente; falha não deixa
  transferência parcial.
- Aceite, rejeição e cancelamento são idempotentes para respectivo estado final.
  Ofertas vencidas mudam para `expired` e liberam cartas.
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
- Returno espelha turno com casa/fora invertidos.
- Fixture list fixa e determinística em `src/domain/calculators/schedule.ts`.
- `season_start` usa mesma fixture list no Postgres e só inicia com seleção
  persistida de exatamente 6 clubes elegíveis.

## Temporada e classificação

- Estados operacionais expostos ao app: `waiting_for_clubs`, `ready_to_start`,
  `active`, `finished`.
- Enquanto houver menos de 6 clubes elegíveis, nenhuma temporada inicia e
  nenhuma rodada/partida parcial é criada.
- Se houver mais de 6 clubes elegíveis, admin precisa escolher quais 6 entram;
  não há seleção aleatória.
- Classificação usa somente partidas `finished`: vitória 3 pontos, empate 1,
  derrota 0.
- Desempate: pontos, vitórias, saldo de gols, gols pró, nome do clube e `club_id`
  como critério determinístico final. Confronto direto não foi implementado.
- Prêmios finais são valores inteiros em centavos, configurados por posição e
  creditados uma única vez como `season_prize` no ledger.

## Janela diária (América/Belém)

- **21:55**: fechamento automático de escalações (`rounds.lineup_lock_at`).
- **22:00**: início da rodada (`rounds.starts_at`).
- **22:10**: rodada finalizada (`rounds.ends_at`).
- Processador usa timestamps persistidos em cada rodada. Não há horário
  hardcoded no cron; atraso do servidor executa etapas vencidas em ordem.
- `rounds.lineups_locked_at`, `rounds.simulation_started_at` e
  `rounds.finalized_at` registram execução operacional de cada etapa.

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
  approved cujo clube seja mandante ou visitante da partida.
- Usuário approved estranho à partida não vê `match_events`, mesmo depois de
  `reveal_at`, com data passada ou partida `finished`.
- Pending, blocked e anon não acessam resumo nem eventos.
- Resumo de partida não inclui evento, descrição, minuto a minuto, jogador do
  evento, escalação privada, tática, seed ou payload de simulação.
- Client não insere, atualiza nem deleta `match_events`.

## Simulador determinístico de partidas

- Versão atual: `SIMULATION_VERSION = 1`.
- Seed persistida por partida: `season_id:round_id:match_id:simulation_version`.
- Motor TypeScript puro usa PRNG determinístico derivado da seed; RPC SQL usa
  `md5(seed:contador)` para gerar rolagens determinísticas sem `random()`.
- Escalação manual válida e salva antes de `rounds.lineup_lock_at` tem prioridade.
  Quando ausente ou inválida, simulação gera escalação automática.
- Escalação automática usa somente cartas elegíveis do clube, sem repetição, na
  ordem: posição natural do slot, menor penalidade de improviso, maior OVR
  efetivo, maior OVR base, identificador estável.
- Fallback automático usa `1-2-1-1` e `balanced`.
- Snapshot histórico fica em `match_lineup_snapshots` com origem
  `manual`/`automatic`, formação, estilo, posição natural, posição usada, OVR
  base, OVR efetivo, penalidade e atributos.
- Forças são limitadas a `0..100`: ataque, defesa, goleiro e geral.
- Modificadores de formação:
  - `1-2-1-1`: ataque `0.98`, defesa `1.08`, chances `0.96`, exposição `0.88`.
  - `1-1-2-1`: ataque `1.02`, defesa `0.99`, chances `1.08`, exposição `1.00`.
  - `1-1-1-2`: ataque `1.10`, defesa `0.92`, chances `1.06`, exposição `1.12`.
  - `0-2-2-1`: ataque `1.05`, defesa `0.94`, chances `1.10`, exposição `1.20`.
- Estilos reutilizam contrato atual: `balanced` neutro, `offensive` ataque
  `1.10` e defesa `0.90`, `defensive` ataque `0.90` e defesa `1.10`.
- Eventos gravados: `match_started`, `chance`, `shot`, `save`, `goal`,
  `halftime`, `match_finished`. Placar final vem dos eventos de gol.
- Estatísticas por clube ficam em `match_statistics`: posse, chances,
  finalizações, finalizações no alvo, defesas e gols.
- Prêmios de partida usam `match_reward_config`: vitória `75`, empate `25`,
  derrota `0` cents por padrão. Crédito passa por `_credit_wallet`; prêmios
  zero também geram ledger.
- `simulate_match` e `simulate_round` são RPCs admin-only e idempotentes para
  operação manual. Cron chama `process_due_rounds(now())` com service role.
- Em `starts_at`, rodada simula partidas e credita `match_reward`, mas não
  marca `rounds.is_processed`.
- Em `ends_at`, `round_finalize` exige exatamente 3 partidas `finished`, marca
  `rounds.is_processed = true` e preenche `rounds.finalized_at`.
- Última rodada finalizada dispara encerramento da temporada quando existem
  10 rodadas e 30 partidas `finished`; `season_prize` continua sendo creditado
  uma única vez por clube.
- Teste estatístico TypeScript roda 2.000 seeds fixas por cenário. Faixas:
  times iguais com diferença de vitórias menor que `8%`, time superior vence
  entre `50%` e `90%`, empates acima de `8%`, média de gols entre `1.8` e `4.8`,
  placares com 8+ gols abaixo de `4%`. Faixas cobrem variância fixa sem
  permitir vitória garantida.
