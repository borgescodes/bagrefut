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
bun run format:check
bun run lint
bun run check:pwa
bun run check
bun run build
```

`bun run test` usa Vitest; nao use `bun test`. O `check` valida package manager,
Prettier, ESLint, TypeScript, Vitest, assets/manifest PWA e build.

O deploy deve preservar `.gitattributes`: LF e padrao do repo; scripts Windows
ficam CRLF; binarios ficam marcados como binarios.

## PWA em producao

- Lovable deve servir `/manifest.webmanifest`, `/sw.js`, `/favicon.ico`,
  `/apple-touch-icon.png` e os icones PWA.
- A instalacao PWA depende de HTTPS em producao.
- O service worker gerado por `vite-plugin-pwa` faz precache somente de assets
  estaticos versionados do build. Nao configurar runtime caching para Supabase,
  Auth, RPCs ou qualquer dado privado.
- Nao comunicar suporte offline total enquanto nao existir desenho explicito de
  offline para dados privados.

Testes SQL em `supabase/tests/database/*.sql` sao executados manualmente no SQL
Editor Lovable: primeiro a migration, depois o teste SQL, mantendo
transacao/rollback quando o teste tiver esse preparo.

## Mercado utilizável

1. Aplique `supabase/migrations/20260710120000_usable_market.sql` pelo fluxo de
   migrations do Lovable/Supabase. Não altere migrations anteriores já aplicadas.
2. Em ambiente de teste, execute
   `supabase/tests/database/usable_market.sql` completo. Preserve `BEGIN` e
   `ROLLBACK`; confirme `NOTICE: usable_market contract test passed`.
3. Regere os tipos somente depois da migration existir no banco:

```powershell
supabase gen types typescript --project-id <PROJECT_ID> --schema public |
  Set-Content -Encoding utf8 src/integrations/supabase/types.ts
```

Para Supabase local iniciado, troque `--project-id <PROJECT_ID>` por `--local`.
Rode `bun run check` após regenerar. Até essa regeneração, os RPCs novos ficam
centralizados em um único helper com cast controlado e validação Zod; não espalhe
casts pelo frontend.

## Cron / rodadas automaticas

O processamento usa um unico job por minuto:

```sql
SELECT public.process_due_rounds(now());
```

A migration `20260709170000_operational_automation.sql` tenta registrar
`bagrefut-process-due-rounds` via `pg_cron`. Se `pg_cron` nao estiver
disponivel, configure um scheduler externo para chamar:

```http
POST /api/internal/jobs/process-due-rounds
Authorization: Bearer <INTERNAL_JOB_SECRET>
```

Nao criar tres crons fixos para 21:55, 22:00 e 22:10; esses horarios vivem em
`rounds.lineup_lock_at`, `rounds.starts_at` e `rounds.ends_at`.

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
