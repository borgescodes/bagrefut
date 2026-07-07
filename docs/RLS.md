# Row-Level Security

Todas as 22 tabelas tem RLS habilitado. Resumo do modelo depois das migrations
corretivas:

| Tabela                   | Autenticado le                          | Autenticado escreve             |
| ------------------------ | --------------------------------------- | ------------------------------- |
| `profiles`               | Proprio; admin approved le tudo         | Nenhum; status so por RPC       |
| `user_roles`             | Approved: propria role; admin le tudo   | Nenhum; so service_role         |
| `leagues`                | Apenas approved                         | Nenhum                          |
| `club_badges`            | Apenas approved, ativos                 | Nenhum                          |
| `clubs`                  | Apenas approved                         | Nenhum; so RPCs                 |
| `players`                | Apenas approved                         | Nenhum                          |
| `club_players`           | Approved: proprio clube; admin le tudo  | Nenhum; so RPCs                 |
| `initial_packs`          | Approved: proprio pacote; admin le tudo | Nenhum; so RPCs                 |
| `initial_pack_items`     | Approved: proprio pacote; admin le tudo | Nenhum                          |
| `wallet_transactions`    | Approved: proprio ledger; admin le tudo | Nenhum; ledger imutavel         |
| `seasons`                | Apenas approved                         | Nenhum                          |
| `rounds`                 | Apenas approved                         | Nenhum                          |
| `matches`                | Apenas approved                         | Nenhum                          |
| `match_events`           | Approved; nao-admin so revelado         | Nenhum                          |
| `lineups`                | Approved: propria/admin/liberada        | Nenhum; so `save_lineup`        |
| `lineup_players`         | Approved: propria/admin/liberada        | Nenhum; so `save_lineup`        |
| `training_sessions`      | Approved: proprios treinos; admin tudo  | Nenhum; so RPC pendente         |
| `market_listings`        | Apenas approved                         | Nenhum; so RPC pendente         |
| `transfer_offers`        | Approved: ofertas proprias; admin tudo  | Nenhum; so RPC pendente         |
| `transfer_offer_items`   | Approved: itens de ofertas proprias     | Nenhum                          |
| `push_subscriptions`     | Approved: proprias; admin le tudo       | Approved gerencia proprias      |
| `admin_audit_logs`       | Apenas admin approved                   | Nenhum; so funcoes seguras      |

Nenhuma tabela concede acesso a `anon`.

Usuarios `pending` e `blocked` leem somente o proprio `profiles` para detectar
status. Eles nao acessam dados do jogo diretamente via API Supabase. Admin so
tem acesso administrativo quando o proprio profile tambem esta `approved`.

## Funcoes `SECURITY DEFINER`

Todas seguem o padrao obrigatorio:

- `SET search_path = ''`
- referencias totalmente qualificadas (`public.<t>`, `auth.uid()`)
- validam `auth.uid()` e permissao do chamador internamente quando mutam dados
- `REVOKE ALL FROM PUBLIC, anon` + `GRANT` apenas ao role minimo

| Funcao                                             | Grant         | Uso                                  |
| -------------------------------------------------- | ------------- | ------------------------------------ |
| `public.has_role(uuid, app_role)`                  | authenticated | Helper de roles em policies          |
| `public.is_approved_user(uuid)`                    | authenticated | Helper approved seguro para policies |
| `public.handle_new_user()`                         | service_role  | Trigger `on_auth_user_created`       |
| `public._credit_wallet(...)`                       | service_role  | Interna; chamada por RPCs            |
| `public._debit_wallet(...)`                        | service_role  | Interna; chamada por RPCs            |
| `public.create_club(name, abbr, badge)`            | authenticated | Cria clube atomico + saldo + pacote  |
| `public.open_initial_pack(club_id)`                | authenticated | Sorteia pacote inicial atomico       |
| `public.save_lineup(round, formation, style, json)`| authenticated | Salva escalacao validada             |
| `public.admin_set_user_status(target,status,reason)` | authenticated | Status + audit atomicos            |

`admin_set_user_status` atualiza `profiles.status` e insere
`admin_audit_logs` na mesma transacao. Reset de senha admin usa Supabase Auth
Admin API e depois grava audit em Postgres; Auth e Postgres nao sao uma unica
transacao reversivel, entao falha de audit apos senha alterada retorna erro
explicito.
