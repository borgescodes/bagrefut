# Setup local & primeiro admin

## Variáveis de ambiente

Este projeto usa Lovable Cloud. Arquivo `.env` fica versionado porque Lovable
precisa dele neste repositório. Deve conter apenas chaves públicas ou valores
seguros para esse fluxo. Segredos administrativos continuam fora do client e
não devem ser expostos em variáveis `VITE_*`.

Chaves relevantes:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_PUBLISHABLE_KEY`
- `VITE_SUPABASE_PROJECT_ID`
- `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`
- `SUPABASE_SERVICE_ROLE_KEY` somente no servidor/ambiente seguro, nunca no
  client nem em `VITE_*`

## Rodar

```bash
bun install --frozen-lockfile
bun run dev
```

Bun é gerenciador canônico. `bun.lock` é único lockfile versionado; não rode
`npm install`, `npm ci`, `pnpm` ou `yarn`. Scripts aceitam `npm run <script>`
quando `node_modules` já estiver instalado, mas npm não é gerenciador de
instalação do projeto.

## Scripts

```bash
bun run test
bun run test:watch
bun run test:coverage
bun run typecheck
bun run format
bun run format:check
bun run check
bun run check:pwa
bun run build
bun run lint
```

`bun run test` usa Vitest. Evite `bun test`.

`bun run format` aplica Prettier. `bun run format:check` valida formatação.

`bun run check` executa, nesta ordem: política de package manager, Prettier,
ESLint, TypeScript, Vitest, validação PWA, validação de assets e build.

Repo usa LF por padrão via `.gitattributes`. Windows scripts (`.bat`, `.cmd`,
`.ps1`) permanecem CRLF; assets binários não são normalizados.

## PWA local

Para validar instalação local:

```bash
bun run build
bun run preview
```

No preview, confira `/manifest.webmanifest`, `/sw.js`, `/favicon.ico`,
`/apple-touch-icon.png` e ícones PWA. Service worker é registrado apenas em
produção e pode ser desativado com `?sw=off`. Cache é conservador: somente
arquivos estáticos versionados do build, sem cache de Supabase, Auth, RPCs ou
dados privados. Instalação PWA real em produção exige HTTPS.

## Testes SQL

Testes em `supabase/tests/database/*.sql` são manuais no SQL Editor Lovable.
Aplique migration antes de executar teste correspondente. Preserve
`BEGIN`/`ROLLBACK` quando arquivo já estiver preparado assim.

Arquivos principais:

- `admin_audit_and_game_rls.sql`
- `club_identity_security.sql`
- `closed_market_economy.sql`
- `fair_starter_packs.sql`
- `match_events_rls.sql`
- `open_initial_pack_concurrency.sql`
- `player_market_training.sql`
- `save_lineup_security.sql`

Pacotes balanceados:

1. aplique `supabase/migrations/20260713160000_fair_starter_packs.sql`;
2. execute `supabase/tests/database/fair_starter_packs.sql`;
3. confirme saída:

```text
NOTICE: fair_starter_packs contract test passed
ROLLBACK
```

Migration possui preflight e falha se houver pacote aberto, carta já atribuída,
mais de seis clubes, código ausente ou OVR diferente da definição aprovada.

## Promover primeiro admin (executar uma vez, via SQL)

Depois que usuário destino se cadastrar e for aprovado:

```sql
-- 1) Aprove perfil, se ainda não estiver aprovado
UPDATE public.profiles SET status = 'approved' WHERE username = 'seu_username_aqui';

-- 2) Insira papel admin
INSERT INTO public.user_roles (user_id, role)
SELECT id, 'admin' FROM public.profiles WHERE username = 'seu_username_aqui'
ON CONFLICT (user_id, role) DO NOTHING;
```

A partir daí, painel `/admin` fica disponível para esse usuário.

## Cadastro / login

- Usuários novos entram em `/cadastro`, escolhem username (3-16, letras e
  números) e senha (mín. 8, com letra e número). E-mail interno é derivado
  automaticamente (`{username}@bagrefut.local`) - usuário nunca vê e-mail.
- Após cadastro, conta fica `pending`. Admin aprova em `/admin`.
- Login em `/login` com username + senha.
