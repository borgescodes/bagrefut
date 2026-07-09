# Setup local & primeiro admin

## Variáveis de ambiente

Este projeto usa Lovable Cloud. O arquivo `.env` fica versionado porque o
Lovable precisa dele neste repositório. Ele deve conter apenas chaves públicas
ou valores seguros para esse fluxo. Segredos administrativos continuam fora do
client e não devem ser expostos em variáveis `VITE_*`.

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

Bun e o gerenciador canonico. `bun.lock` e o unico lockfile versionado; nao rode
`npm install`, `npm ci`, `pnpm` ou `yarn`. Os scripts aceitam `npm run <script>`
quando `node_modules` ja estiver instalado, mas npm nao e o gerenciador de
instalacao do projeto.

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

`bun run format` aplica Prettier. `bun run format:check` valida formatacao.

`bun run check` executa, nesta ordem: politica de package manager, Prettier,
ESLint, TypeScript, Vitest, validacao PWA e build.

O repo usa LF por padrao via `.gitattributes`. Windows scripts (`.bat`, `.cmd`,
`.ps1`) permanecem CRLF; assets binarios nao sao normalizados.

## PWA local

Para validar instalacao local:

```bash
bun run build
bun run preview
```

No preview, confira `/manifest.webmanifest`, `/sw.js`, `/favicon.ico`,
`/apple-touch-icon.png` e os icones PWA. O service worker e registrado apenas em
producao e pode ser desativado com `?sw=off`. O cache e conservador: somente
arquivos estaticos versionados do build, sem cache de Supabase, Auth, RPCs ou
dados privados. Instalacao PWA real em producao exige HTTPS.

Testes SQL em `supabase/tests/database/*.sql` sao manuais no SQL Editor Lovable.
A ordem correta e aplicar a migration primeiro e executar o teste SQL depois,
preservando transacao/rollback quando o teste ja estiver preparado assim.

Arquivos SQL existentes:

- `admin_audit_and_game_rls.sql`
- `club_identity_security.sql`
- `match_events_rls.sql`
- `open_initial_pack_concurrency.sql`
- `player_market_training.sql`
- `save_lineup_security.sql`

## Promover o primeiro admin (executar uma vez, via SQL)

Depois que o usuário destino se cadastrar e for aprovado:

```sql
-- 1) Aprove o perfil (se ainda não estiver aprovado)
UPDATE public.profiles SET status = 'approved' WHERE username = 'seu_username_aqui';

-- 2) Insira o papel admin
INSERT INTO public.user_roles (user_id, role)
SELECT id, 'admin' FROM public.profiles WHERE username = 'seu_username_aqui'
ON CONFLICT (user_id, role) DO NOTHING;
```

A partir daí, o painel `/admin` fica disponível para esse usuário.

## Cadastro / login

- Usuários novos entram em `/cadastro`, escolhem username (3-16, letras e
  números) e senha (mín. 8, com letra e número). O e-mail interno é derivado
  automaticamente (`{username}@bagrefut.local`) — o usuário nunca vê e-mail.
- Após cadastro, a conta fica `pending`. O admin aprova em `/admin`.
- Login em `/login` com username + senha.
