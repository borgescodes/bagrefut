# Row-Level Security

Todas as 24 tabelas tem RLS habilitado. Resumo do modelo depois das migrations
corretivas:

| Tabela                           | Autenticado le                                           | Autenticado escreve            |
| -------------------------------- | -------------------------------------------------------- | ------------------------------ |
| `profiles`                       | Proprio; admin approved le tudo                          | Nenhum; status so por RPC      |
| `user_roles`                     | Approved: propria role; admin le tudo                    | Nenhum; so service_role        |
| `leagues`                        | Apenas approved                                          | Nenhum                         |
| `club_badges`                    | Approved ativos; admin approved todos                    | Nenhum                         |
| `clubs`                          | Apenas approved                                          | Nenhum; so RPCs                |
| `players`                        | Apenas approved                                          | Nenhum                         |
| `club_players`                   | Approved: proprio clube e estoque; admin le tudo         | Nenhum; so RPCs                |
| `system_market_stock`            | Approved le estoque; admin approved le estoque           | Nenhum; so RPCs/service        |
| `initial_packs`                  | Approved: proprio pacote; admin le tudo                  | Nenhum; so RPCs                |
| `initial_pack_items`             | Approved: proprio pacote; admin le tudo                  | Nenhum                         |
| `wallet_transactions`            | Approved: proprio ledger; admin le tudo                  | Nenhum; ledger imutavel        |
| `seasons`                        | Apenas approved                                          | Nenhum                         |
| `rounds`                         | Apenas approved                                          | Nenhum                         |
| `matches`                        | Sem SELECT direto para authenticated; usar resumo seguro | Nenhum                         |
| `match_events`                   | Approved participante; admin approved tudo               | Nenhum direto                  |
| `lineups`                        | Approved: propria/admin/liberada                         | Nenhum; so `save_lineup`       |
| `lineup_players`                 | Approved: propria/admin/liberada                         | Nenhum; so `save_lineup`       |
| `training_sessions`              | Approved: proprios treinos; admin tudo                   | Nenhum; so `train_club_player` |
| `club_player_attribute_progress` | Approved: progresso das proprias cartas; admin tudo      | Nenhum; so RPC                 |
| `market_listings`                | Apenas approved                                          | Nenhum; so RPC pendente        |
| `transfer_offers`                | Approved: ofertas proprias; admin tudo                   | Nenhum; so RPC pendente        |
| `transfer_offer_items`           | Approved: itens de ofertas proprias                      | Nenhum                         |
| `push_subscriptions`             | Approved: proprias; admin le tudo                        | Approved gerencia proprias     |
| `admin_audit_logs`               | Apenas admin approved                                    | Nenhum; so funcoes seguras     |

Nenhuma tabela concede acesso a `anon`.

Usuarios `pending` e `blocked` leem somente o proprio `profiles` para detectar
status. Eles nao acessam dados do jogo diretamente via API Supabase. Admin so
tem acesso administrativo quando o proprio profile tambem esta `approved`.

## Partidas e eventos

- `public.match_events` tem `ENABLE ROW LEVEL SECURITY` e `FORCE ROW LEVEL SECURITY`.
- A unica policy de leitura esperada e
  `match_events_approved_participant_or_admin_read`.
- Usuario approved le eventos completos somente quando seu clube participa da
  partida como mandante ou visitante.
- Admin precisa ter role `admin` e profile `approved` para ler eventos de
  qualquer partida.
- Usuarios approved sem participacao na partida veem somente placar/resumo por
  `public.list_match_score_summaries(uuid)`.
- Pending, blocked e anon nao acessam resumo nem eventos.
- `reveal_at`, `now()`, `status='finished'` e data passada nao liberam eventos
  completos de partidas alheias.
- `authenticated` e `anon` nao tem `INSERT`, `UPDATE` ou `DELETE` em
  `match_events`; simulacao deve escrever por backend confiavel/service role ou
  RPC administrativa existente.
- `matches` contem campos internos como `seed`; por isso o client nao deve usar
  SELECT direto da tabela base para resumo publico.

## Funcoes `SECURITY DEFINER`

Todas seguem o padrao obrigatorio:

- `SET search_path = ''`
- referencias totalmente qualificadas (`public.<t>`, `auth.uid()`)
- validam `auth.uid()` e permissao do chamador internamente quando mutam dados
- `REVOKE ALL FROM PUBLIC, anon` + `GRANT` apenas ao role minimo

| Funcao                                               | Grant         | Uso                                  |
| ---------------------------------------------------- | ------------- | ------------------------------------ |
| `public.has_role(uuid, app_role)`                    | authenticated | Helper de roles em policies          |
| `public.is_approved_user(uuid)`                      | authenticated | Helper approved seguro para policies |
| `public.user_participates_in_match(uuid, uuid)`      | authenticated | Helper seguro de mandante/visitante  |
| `public.list_match_score_summaries(uuid)`            | authenticated | Resumo seguro de partidas            |
| `public.handle_new_user()`                           | service_role  | Trigger `on_auth_user_created`       |
| `public._credit_wallet(...)`                         | service_role  | Interna; chamada por RPCs            |
| `public._debit_wallet(...)`                          | service_role  | Interna; chamada por RPCs            |
| `public.create_club(name, abbr, badge)`              | authenticated | Cria clube atomico + saldo + pacote  |
| `public.update_club_identity(club,name,abbr,badge)`  | authenticated | Edita identidade do clube via regras |
| `public.open_initial_pack(club_id)`                  | authenticated | Sorteia pacote inicial atomico       |
| `public.save_lineup(round, formation, style, json)`  | authenticated | Salva escalacao validada             |
| `public.sell_player_to_system(club_player_id)`       | authenticated | Vende carta ao sistema por 50%       |
| `public.buy_player_from_system(club_player_id)`      | authenticated | Compra carta do sistema por 100%     |
| `public.train_club_player(club_player_id, attr)`     | authenticated | Treino diario atomico                |
| `public.admin_set_user_status(target,status,reason)` | authenticated | Status + audit atomicos              |

Funcoes puras auxiliares (`calculate_player_overall`,
`calculate_reference_value_cents`, `training_cost_cents`) tambem usam
`SET search_path = ''`, referencias qualificadas e grants explicitos.

`admin_set_user_status` atualiza `profiles.status` e insere
`admin_audit_logs` na mesma transacao. Reset de senha admin usa Supabase Auth
Admin API e depois grava audit em Postgres; Auth e Postgres nao sao uma unica
transacao reversivel, entao falha de audit apos senha alterada retorna erro
explicito.
