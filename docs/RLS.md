# Row-Level Security

Todas as tabelas listadas abaixo têm RLS habilitado. Resumo do modelo após as
migrations corretivas:

| Tabela                           | Autenticado lê                                         | Autenticado escreve            |
| -------------------------------- | ------------------------------------------------------ | ------------------------------ |
| `profiles`                       | Próprio; admin approved lê tudo                        | Nenhum; status só por RPC      |
| `user_roles`                     | Approved: própria role; admin lê tudo                  | Nenhum; só service_role        |
| `leagues`                        | Apenas approved                                        | Nenhum                         |
| `club_badges`                    | Approved ativos; admin approved lê todos               | Nenhum                         |
| `clubs`                          | Apenas approved                                        | Nenhum; só RPCs                |
| `players`                        | Apenas approved                                        | Nenhum                         |
| `club_players`                   | Approved: próprio clube e estoque; admin lê tudo       | Nenhum; só RPCs/service        |
| `system_market_stock`            | Approved lê estoque; admin approved lê estoque         | Nenhum; só RPCs/service        |
| `initial_packs`                  | Approved: próprio pacote; admin lê tudo                | Nenhum; só RPCs                |
| `initial_pack_items`             | Approved: próprio pacote; admin lê tudo                | Nenhum                         |
| `wallet_transactions`            | Approved: próprio ledger; admin lê tudo                | Nenhum; ledger imutável        |
| `season_configurations`          | Apenas admin approved                                  | Nenhum direto; só RPC admin    |
| `season_config_participants`     | Apenas admin approved                                  | Nenhum direto; só RPC admin    |
| `season_prize_config`            | Apenas admin approved                                  | Nenhum direto; só RPC admin    |
| `seasons`                        | Apenas approved                                        | Nenhum                         |
| `season_participants`            | Apenas approved                                        | Nenhum                         |
| `season_final_standings`         | Apenas approved                                        | Nenhum                         |
| `rounds`                         | Apenas approved                                        | Nenhum                         |
| `matches`                        | Sem SELECT direto para authenticated; usar RPC segura  | Nenhum                         |
| `match_events`                   | Approved conforme política da partida; admin lê tudo   | Nenhum direto                  |
| `match_lineup_snapshots`         | Approved após partida finished                         | Nenhum direto                  |
| `match_statistics`               | Approved após partida finished                         | Nenhum direto                  |
| `lineups`                        | Approved: própria/admin/liberada                       | Nenhum; só `save_lineup`       |
| `lineup_players`                 | Approved: própria/admin/liberada                       | Nenhum; só `save_lineup`       |
| `training_sessions`              | Approved: próprios treinos; admin lê tudo              | Nenhum; só `train_club_player` |
| `club_player_attribute_progress` | Approved: progresso das próprias cartas; admin lê tudo | Nenhum; só RPC                 |
| `market_listings`                | Apenas approved; RPC pública expõe somente `open`      | Nenhum; só RPCs de mercado     |
| `transfer_offers`                | Approved: ofertas próprias; admin lê tudo              | Nenhum; só RPCs de oferta      |
| `transfer_offer_items`           | Approved: itens de ofertas próprias                    | Nenhum; só RPCs de oferta      |
| `push_subscriptions`             | Approved: próprias; admin lê tudo                      | Approved gerencia próprias     |
| `admin_audit_logs`               | Apenas admin approved                                  | Nenhum; só funções seguras     |
| `operational_job_runs`           | Nenhum direto; admin via RPC                           | Nenhum; service_role apenas    |

Nenhuma tabela concede acesso a `anon`.

Usuários `pending` e `blocked` leem somente o próprio `profiles` para detectar
status. Eles não acessam dados do jogo diretamente via API Supabase. Admin só
tem acesso administrativo quando o próprio profile também está `approved`.

## Partidas, eventos e simulação

- `public.match_events` usa RLS e `FORCE ROW LEVEL SECURITY`.
- Usuários approved acessam eventos conforme a política vigente para a partida.
- Admin precisa ter role `admin` e profile `approved` para simular ou consultar
  dados administrativos.
- Resumos públicos usam `public.list_match_score_summaries(uuid)`.
- Detalhes públicos usam `public.get_match_public_details(uuid)` e não expõem
  seed nem campos internos.
- Pending, blocked e anon não acessam resumos, detalhes ou eventos.
- `authenticated` e `anon` não recebem `INSERT`, `UPDATE` ou `DELETE` direto em
  `matches`, `match_events`, `match_lineup_snapshots` ou `match_statistics`.
- `public.simulate_match(uuid)` e `public.simulate_round(uuid)` validam admin
  approved internamente.
- Os cores internos `_match_simulate_internal`, `_round_simulate_internal`,
  `_round_finalize_internal` e `_season_finish_internal` nao dependem de
  `auth.uid()` e sao executaveis apenas por `service_role`/`postgres`.
- `public.process_due_rounds(timestamptz)` e
  `public._operational_process_job(...)` sao service-only; `authenticated` nao
  recebe grant. Retry operacional usa `_operational_retry_job_run(uuid)`, tambem
  service-only.
- `public.admin_list_operational_job_runs(limit,status)` valida admin approved e
  e o unico caminho autenticado para leitura de `operational_job_runs`.
- A simulação persiste snapshots, estatísticas, eventos, placar e prêmio por RPC
  transacional.
- Índices únicos e bloqueio da partida evitam duplicação de simulação, eventos,
  snapshots e prêmio.

## Funções `SECURITY DEFINER`

Todas seguem o padrão obrigatório:

- `SET search_path = ''`
- referências totalmente qualificadas (`public.<t>`, `auth.uid()`)
- validação interna de autenticação e permissão para operações mutáveis
- `REVOKE ALL FROM PUBLIC, anon`
- `GRANT EXECUTE` apenas ao role mínimo necessário

| Função                                                 | Grant         | Uso                                        |
| ------------------------------------------------------ | ------------- | ------------------------------------------ |
| `public.has_role(uuid, app_role)`                      | authenticated | Helper de roles em policies                |
| `public.is_approved_user(uuid)`                        | authenticated | Helper approved para policies              |
| `public.user_participates_in_match(uuid, uuid)`        | authenticated | Valida participação na partida             |
| `public.list_match_score_summaries(uuid)`              | authenticated | Resumo seguro de partidas                  |
| `public.get_match_public_details(uuid)`                | authenticated | Detalhe público sem seed                   |
| `public.handle_new_user()`                             | service_role  | Trigger `on_auth_user_created`             |
| `public._credit_wallet(...)`                           | service_role  | Crédito interno de carteira                |
| `public._debit_wallet(...)`                            | service_role  | Débito interno de carteira                 |
| `public.create_club(name, abbr, badge)`                | authenticated | Cria clube, saldo e pacote atomicamente    |
| `public.update_club_identity(club,name,abbr,badge)`    | authenticated | Edita identidade do clube                  |
| `public.open_initial_pack(club_id)`                    | authenticated | Abre pacote inicial atomicamente           |
| `public.save_lineup(round, formation, style, json)`    | authenticated | Salva escalação validada                   |
| `public.sell_player_to_system(club_player_id)`         | authenticated | Vende carta ao sistema                     |
| `public.buy_player_from_system(club_player_id)`        | authenticated | Compra carta do sistema                    |
| `public.train_club_player(club_player_id, attr)`       | authenticated | Executa treino diário                      |
| `public.list_market_listings(...)`                     | authenticated | Lista anúncios abertos filtrados           |
| `public.create_market_listing(card,price)`             | authenticated | Cria anúncio e reserva carta               |
| `public.cancel_market_listing(listing)`                | authenticated | Cancela anúncio do vendedor                |
| `public.buy_market_listing(listing)`                   | authenticated | Compra P2P com dois ledgers                |
| `public.list_my_transfer_offers()`                     | authenticated | Lista ofertas recebidas/enviadas           |
| `public.create_transfer_offer(...)`                    | authenticated | Cria oferta e reserva todas as cartas      |
| `public.accept_transfer_offer(offer)`                  | authenticated | Executa troca e cash atomicamente          |
| `public.reject_transfer_offer(offer)`                  | authenticated | Rejeita e libera reservas                  |
| `public.cancel_transfer_offer(offer)`                  | authenticated | Cancela e libera reservas                  |
| `public.list_trade_targets()`                          | authenticated | Lista clubes elegíveis para troca          |
| `public.get_trade_target_roster(club)`                 | authenticated | Lista cartas elegíveis do destinatário     |
| `public.admin_set_user_status(target,status,reason)`   | authenticated | Atualiza status e grava auditoria          |
| `public.list_season_club_eligibility(include_private)` | authenticated | Lista elegibilidade pública/admin          |
| `public.get_season_operational_state()`                | authenticated | Estado operacional da temporada            |
| `public.get_current_round_state()`                     | authenticated | Rodada atual definida pelo backend         |
| `public.get_season_standings(season)`                  | authenticated | Classificação oficial                      |
| `public.get_season_history()`                          | authenticated | Histórico de temporadas                    |
| `public.admin_get_season_setup()`                      | authenticated | Consulta configuração admin                |
| `public.admin_upsert_season_setup(config)`             | authenticated | Salva configuração admin                   |
| `public.admin_set_season_participants(config,clubs)`   | authenticated | Persiste seleção dos clubes                |
| `public.season_start(config)`                          | authenticated | Inicia temporada atomicamente              |
| `public.season_finish(season)`                         | authenticated | Encerra e premia temporada                 |
| `public.simulate_match(match_id)`                      | authenticated | Admin simula partida de forma idempotente  |
| `public.simulate_round(round_id)`                      | authenticated | Admin simula rodada manualmente            |
| `public.admin_list_operational_job_runs(limit,status)` | authenticated | Admin consulta ultimas execucoes           |
| `public.process_due_rounds(now)`                       | service_role  | Processa etapas operacionais vencidas      |
| `public._operational_retry_job_run(job_run)`           | service_role  | Reenfileira failed/dead preservando result |
| `public._expire_transfer_offers(now)`                  | service_role  | Expira ofertas e libera cartas             |

Funções puras auxiliares, como `calculate_player_overall`,
`calculate_reference_value_cents` e `training_cost_cents`, também usam
`SET search_path = ''`, referências qualificadas e grants explícitos.

`admin_set_user_status` atualiza `profiles.status` e insere
`admin_audit_logs` na mesma transação. Reset de senha admin usa Supabase Auth
Admin API e depois grava auditoria em Postgres. Auth e Postgres não formam uma
única transação reversível, então falha de auditoria após senha alterada retorna
erro explícito.
