# Deploy

Projeto roda em Lovable (TanStack Start em Cloudflare Workers) com Lovable Cloud
(Supabase gerenciado).

## Publicação

- **Publish** dentro da própria Lovable (botão "Publish"). Aplica automaticamente
  todas as migrations do repositório contra o Supabase gerenciado.

## Cron / rodadas automáticas

Ainda pendente. Quando implementado, usar `pg_cron` + `pg_net` para chamar
uma rota `/api/public/hooks/*` no servidor TanStack:

- 21:55 America/Belem: `lock-lineups` (marca `rounds.lineup_lock_at` cumprido).
- 22:00 America/Belem: `run-round` (simula todas as partidas da rodada, gera
  `match_events` com `reveal_at` progressivo).
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
