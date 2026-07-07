# Row-Level Security

Todas as 22 tabelas têm RLS habilitado. Resumo do modelo:

| Tabela                   | Autenticado lê                          | Autenticado escreve             |
| ------------------------ | --------------------------------------- | ------------------------------- |
| `profiles`               | Próprio; admin lê tudo                  | Apenas admin (`UPDATE`)         |
| `user_roles`             | Próprios papéis; admin lê tudo          | Nenhum (só service_role)        |
| `leagues`                | Sim                                     | Nenhum                          |
| `club_badges`            | Sim (ativos)                            | Nenhum                          |
| `clubs`                  | Todos os clubes                         | **Nenhum** (só RPCs)            |
| `players`                | Sim (catálogo global)                   | Nenhum                          |
| `club_players`           | Só cartas do próprio clube; admin tudo  | **Nenhum** (só RPCs)            |
| `initial_packs`          | Só pacote do próprio clube              | **Nenhum** (só RPCs)            |
| `initial_pack_items`     | Só itens do próprio pacote              | **Nenhum** (só RPCs)            |
| `wallet_transactions`    | Só ledger do próprio clube              | **Nenhum** (ledger imutável)    |
| `seasons`                | Sim                                     | Nenhum                          |
| `rounds`                 | Sim                                     | Nenhum                          |
| `matches`                | Sim                                     | Nenhum                          |
| `match_events`           | Apenas eventos com `reveal_at ≤ now()` | Nenhum                          |
| `lineups`                | Só própria escalação                    | Sim (INSERT/UPDATE do próprio)  |
| `lineup_players`         | Só própria escalação                    | Sim (ALL do próprio)            |
| `training_sessions`      | Só próprios treinos                     | Nenhum (só RPC pendente)        |
| `market_listings`        | Todos                                   | Nenhum (só RPC pendente)        |
| `transfer_offers`        | Só ofertas que envolvem o próprio clube | Nenhum (só RPC pendente)        |
| `transfer_offer_items`   | Só itens de ofertas próprias            | Nenhum                          |
| `push_subscriptions`     | Próprias                                | Sim (INSERT/DELETE próprias)    |
| `admin_audit_logs`       | Apenas admin                            | Nenhum (só service_role)        |

**Nenhuma tabela concede acesso a `anon`** — anonymous não lê nada.

## Funções `SECURITY DEFINER`

Todas seguem o padrão obrigatório:
- `SET search_path = ''`
- Referências totalmente qualificadas (`public.<t>`, `auth.uid()`)
- Validam `auth.uid()` e permissão do chamador internamente
- `REVOKE ALL FROM PUBLIC, anon` + `GRANT` apenas ao role mínimo

| Função                                      | Grant       | Uso                                     |
| ------------------------------------------- | ----------- | --------------------------------------- |
| `public.has_role(uuid, app_role)`           | authenticated | Chamada pelas policies de RLS          |
| `public.handle_new_user()`                  | service_role  | Trigger `on_auth_user_created`         |
| `public._credit_wallet(...)`                | service_role  | Interno — chamada por outras RPCs      |
| `public._debit_wallet(...)`                 | service_role  | Interno — chamada por outras RPCs      |
| `public.create_club(name, abbr, badge)`     | authenticated | Cria clube atômico + saldo + pacote    |
| `public.open_initial_pack(club_id)`         | authenticated | Sorteia 10 cartas atômico, sem reroll  |
