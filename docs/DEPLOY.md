# Deploy

Projeto roda em Lovable (TanStack Start em Cloudflare Workers) com Lovable Cloud
(Supabase gerenciado).

## Publicação

- **Publish** dentro da própria Lovable (botão "Publish"). Aplica automaticamente
  todas as migrations do repositório contra o Supabase gerenciado.

## Validacao antes de publicar

Use Bun como gerenciador canonico e mantenha `bun.lock` como unico lockfile.
Nao rode `npm install`; `npm run <script>` e aceito apenas para executar scripts
quando `node_modules` ja existe.

```bash
bun install --frozen-lockfile
bun run test
bun run test:coverage
bun run typecheck
bun run check
bun run build
bun run lint
```

`bun run test` usa Vitest; nao use `bun test`. O `check` valida package manager,
TypeScript, Vitest e build, sem lint por enquanto por causa de ruido global
preexistente de CRLF/Prettier.

Testes SQL em `supabase/tests/database/*.sql` sao executados manualmente no SQL
Editor Lovable: primeiro a migration, depois o teste SQL, mantendo
transacao/rollback quando o teste tiver esse preparo.

## Cron / rodadas automáticas

Ainda pendente. Quando implementado, usar `pg_cron` + `pg_net` para chamar
uma rota `/api/public/hooks/*` no servidor TanStack:

- 21:55 America/Belem: `lock-lineups` (marca `rounds.lineup_lock_at` cumprido).
- 22:00 America/Belem: `run-round` (simula todas as partidas da rodada e gera
  `match_events`; `reveal_at` nao libera eventos de jogos alheios).
- 22:10 America/Belem: `finalize-round` (credita prêmios, marca `is_processed`).

## Segurança

- `SUPABASE_SERVICE_ROLE_KEY` só existe no servidor — nunca chega ao client.
- Ações admin de mutação de senha usam `supabaseAdmin.auth.admin.updateUserById`
  em `src/lib/admin.functions.ts`, registrando `admin_audit_logs`.
- Supabase Auth `updateUserById` e insert em `admin_audit_logs` não formam uma
  única transação Postgres. Não tratar reset de senha + audit como operação
  atômica reversível.

## Lovable Cloud Auth

Checklist operacional:

- Email/password habilitado
- Confirmação de email desativada
- Cadastro de usuário habilitado

Este projeto converte username para e-mail interno `{username}@bagrefut.local`.
Esses e-mails internos não são entregáveis. A recuperação por e-mail não deve
ser usada; o fluxo oficial é WhatsApp + senha temporária gerada pelo admin.
Após alterar configurações no Lovable Cloud, validar cadastro e login
manualmente.
# SQL manual para RLS de eventos

- A migration `supabase/migrations/20260708120000_match_events_rls.sql` deve ser
  rodada manualmente no SQL Editor Lovable.
- Depois, validar com `supabase/tests/database/match_events_rls.sql` em ambiente
  apropriado para impersonation/rollback.
- `reveal_at`, data passada e partida encerrada nao liberam eventos completos
  para jogos alheios; resumo/placar usa `list_match_score_summaries`.
