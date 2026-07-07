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
  de cartas só via RPCs (pendentes: `market_buy`, `transfer_offer_accept`).

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

## Auth

- Username + senha (nunca e-mail no fluxo do usuário).
- E-mail interno derivado: `{username}@bagrefut.local`.
- Cadastro → `profiles.status = 'pending'` via trigger `on_auth_user_created`.
- Admin aprova via `/admin` (RPC service-role no servidor).
- Login em `/login`. `/_authenticated/route.tsx` (ssr:false) redireciona
  para `/login` se não houver sessão.

## PWA

- Manifest + ícone declarados.
- `public/sw.js` mínimo (Push API + notificação; sem cache offline).
- Registro guardado — não roda em dev, preview iframe, ou com `?sw=off`.
- Envio real de push (VAPID keys + sender) fica pendente.
