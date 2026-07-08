# Arquitetura

## Stack

- **TanStack Start v1** (SSR, file-based routing) + **React 19** + **Vite 7**.
- **Tailwind v4** via `src/styles.css`.
- **Lovable Cloud** (Supabase) — Postgres + Auth + Realtime + Edge Functions.
- **Vitest** para testes de domínio (unitários, puros).

## Camadas

```
src/
├── domain/          ← Puro TypeScript. Zero dependência externa.
│   ├── enums.ts
│   ├── types.ts
│   ├── rules/       ← Validadores
│   └── calculators/ ← OVR, multipliers, prices, RNG, schedule
├── lib/             ← Wrappers finos (createServerFn) + utilitários runtime
├── integrations/    ← Auto-gerado (Supabase client / middleware / attacher)
├── routes/          ← Telas técnicas mínimas
└── test/            ← Vitest
supabase/
└── migrations/      ← Fonte da verdade do schema
public/
├── badges/          ← 21 escudos PNG portáveis
├── manifest.webmanifest
└── sw.js            ← Service worker mínimo (Push scaffolding)
```

## Regra de ouro

**Toda regra crítica (financeira, propriedade de carta, resultado de partida,
status de partida, transições de estado) vive no Postgres**, dentro de funções
`SECURITY DEFINER` transacionais. Server functions (`*.functions.ts`) são
wrappers finos que só validam formato e delegam.

- Nenhuma policy `TO anon` em tabelas do jogo.
- Nenhuma policy de `INSERT/UPDATE/DELETE` em `wallet_transactions` para
  usuário — ledger é imutável na camada de acesso.
- Nenhuma policy de `UPDATE` em `clubs` para usuário — saldo só via
  `_credit_wallet`/`_debit_wallet` (executáveis somente por `service_role`
  via RPCs `SECURITY DEFINER`).
- Nenhuma policy de mutação em `club_players` para usuário — transferência
  de cartas só via RPCs. Venda/compra contra o sistema usam
  `sell_player_to_system` e `buy_player_from_system`; mercado P2P e trocas
  continuam pendentes.
- `club_players` é a carta permanente. `club_id IS NULL` representa posse do
  sistema e deve ter linha correspondente em `system_market_stock`; `club_id IS
NOT NULL` representa posse de clube e não pode ter linha no estoque. Constraint
  triggers deferíveis validam essa invariante no fim da transação.
- OVR e preço de referência de `players` são derivados por trigger no Postgres.
  Inserts/updates nunca preservam valores inconsistentes enviados pelo app.

## Partidas

- Server functions de leitura comum usam o cliente autenticado do middleware e
  preservam RLS; service role nao deve devolver eventos proibidos a usuario comum.
- `listMatchSummaries` chama `public.list_match_score_summaries` e retorna
  somente placar/resumo.
- `getMatchDetails` retorna o resumo de uma partida e se a UI pode abrir eventos.
- `getMatchEvents` so consulta `match_events` depois de validar admin ou clube
  mandante/visitante; o banco continua sendo a fonte da verdade por RLS.
- `reveal_at`, data passada e partida encerrada nao mudam autorizacao de eventos.

## Migrations

`supabase/migrations/*.sql` é a fonte da verdade. Qualquer alteração posterior
DEVE gerar uma nova migration — nunca editar SQL manualmente no editor sem
propagar para o repositório.

Migrations já aplicadas:

1. Enums, `user_roles` + `has_role`, `profiles` + trigger, `leagues`
   (seed Bagreleirão), `club_badges` (seed 21 escudos).
2. Ajuste de permissões da função `handle_new_user`.
3. `clubs` (com `balance_cents`), `players`, `club_players`, `initial_packs`,
   `initial_pack_items`, `wallet_transactions`, `_credit_wallet`,
   `_debit_wallet`, `create_club`, `open_initial_pack`.
4. `seasons`, `rounds`, `matches`, `match_events`, `lineups`,
   `lineup_players`, `training_sessions`, `market_listings`,
   `transfer_offers`, `transfer_offer_items`, `push_subscriptions`,
   `admin_audit_logs`.
5. Seed de 60 jogadores.
6. OVR/preço derivados, correção determinística dos 60 jogadores,
   `system_market_stock`, carta permanente, pacote inicial via estoque, mercado
   clube-sistema e treino persistente por carta/atributo.

7. `match_events` participante/admin-approved, helper
   `user_participates_in_match`, resumo seguro `list_match_score_summaries` e
   revogacao de SELECT direto em `matches` para clients.

A migration `supabase/migrations/20260708120000_match_events_rls.sql` deve ser
aplicada manualmente no SQL Editor Lovable. Nao usar Supabase CLI para esse
passo.

## Auth

- Username + senha (nunca e-mail no fluxo do usuário).
- E-mail interno derivado: `{username}@bagrefut.local`.
- E-mails internos `@bagrefut.local` não são entregáveis. Confirmação de
  e-mail deve permanecer desativada no Lovable Cloud; recuperação por e-mail
  não deve ser usada.
- Cadastro → `profiles.status = 'pending'` via trigger `on_auth_user_created`.
- Admin aprova via `/admin` (RPC service-role no servidor).
- Recuperação de senha ocorre via WhatsApp. O admin gera uma senha temporária
  no servidor, recebe o segredo uma vez e entrega por canal seguro.
- Senha temporária grava `auth.users.app_metadata.must_change_password = true`
  preservando demais metadados. Enquanto essa flag estiver ativa,
  `/_authenticated/route.tsx` redireciona qualquer rota autenticada para
  `/trocar-senha`, exceto a própria rota de troca.
- A troca de senha usa `changeTemporaryPassword`, sempre com `context.userId`;
  o client nunca envia `userId` e nenhuma senha é persistida ou auditada.
- Login em `/login`. `/_authenticated/route.tsx` (ssr:false) redireciona
  para `/login` se não houver sessão.

- Supabase Auth Admin API e `admin_audit_logs` não estão na mesma transação
  Postgres; a arquitetura não alega atomicidade entre esses dois sistemas.

## PWA

- Manifest pt-BR em `public/manifest.webmanifest`, com `BagreFut`, descricao
  curta, `start_url`/`scope` em `/`, `display: standalone`, orientacao portrait
  e cores derivadas da identidade escura atual.
- Icones do app ficam em `public/favicon.ico`, `public/apple-touch-icon.png`,
  `public/pwa-192x192.png`, `public/pwa-512x512.png`,
  `public/pwa-maskable-192x192.png` e `public/pwa-maskable-512x512.png`.
- `vite-plugin-pwa` gera `.output/public/sw.js` no build com auto-update e
  precache de assets estaticos versionados. Nao ha runtime caching.
- Supabase, Auth, RPCs e dados privados nao devem ser cacheados pelo service
  worker.
- Registro guardado em `src/lib/pwa.ts`: nao roda em dev, preview iframe, ou
  com `?sw=off`.
- O app continua funcionando sem service worker e nao promete offline total.
- Envio real de push (VAPID keys + sender) fica pendente.

## Tooling

- Bun e o gerenciador canonico; `bun.lock` e o unico lockfile versionado.
- `.gitattributes` define LF por padrao, CRLF apenas para scripts Windows e
  binario para imagens, favicon, fontes e ZIPs.
- Prettier usa `.prettierrc.json` com `endOfLine: "lf"`.
- `bun run check` executa package manager, Prettier, ESLint, TypeScript, Vitest,
  validacao PWA e build.
