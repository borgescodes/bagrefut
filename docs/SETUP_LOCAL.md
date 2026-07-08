# Setup local & primeiro admin

## Variáveis de ambiente

Este projeto usa Lovable Cloud — as variáveis já estão configuradas no `.env`
gerado (nunca commitado com valores reais). Para desenvolvimento local,
copie `.env.example` e preencha se necessário. Chaves relevantes:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_PUBLISHABLE_KEY`
- `VITE_SUPABASE_PROJECT_ID`
- `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_SERVICE_ROLE_KEY` (server-only)

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
bun run check
bun run build
bun run lint
```

`bun run test` usa Vitest. Evite `bun test`.

`bun run check` executa, nesta ordem: politica de package manager, TypeScript,
Vitest e build. Lint nao entra no `check` temporariamente porque ha falhas
globais preexistentes de CRLF/Prettier que serao tratadas em batch separado.

Testes SQL em `supabase/tests/database/*.sql` sao manuais no SQL Editor Lovable.
A ordem correta e aplicar a migration primeiro e executar o teste SQL depois,
preservando transacao/rollback quando o teste ja estiver preparado assim.

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
