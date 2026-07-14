# BagreFut

**Monte clube. Gerencie elenco. Domine PGM.**

Fundação técnica do projeto com regras críticas no Postgres, RLS, RPCs
atômicas, domínio TypeScript testado e frontend mobile-first.

## O que já foi construído

- Banco cobrindo perfis, papéis, liga, escudos, clubes, jogadores, cartas,
  pacotes iniciais, temporadas, rodadas, partidas, eventos, escalações,
  treinos, estoque do sistema, mercado, ofertas, ledger, push e auditoria.
- **Saldo por clube** (`clubs.balance_cents`, limitado a R$ 999,99 e nunca
  negativo). Nenhuma policy permite `UPDATE` direto. Mutação de saldo passa
  por `_credit_wallet`/`_debit_wallet` e grava `wallet_transactions`.
- **RPC `create_club`** (`SECURITY DEFINER`, atômica): valida autenticação,
  perfil aprovado, ausência de clube prévio, liga em setup, identidade e
  escudo; cria clube, credita R$ 10,00 e reserva um pacote inicial exclusivo.
- **Seis pacotes balanceados**: `PACK01` a `PACK06`, cada um com 10 cartas
  (2 GK, 3 DEF, 3 MID e 2 ATA), OVR total 578 ou 579 e sem jogador repetido.
- **Carta permanente**: `club_players` representa instância única da carta.
  `club_id IS NOT NULL` significa carta de clube; `club_id IS NULL` significa
  carta no sistema.
- **RPC `open_initial_pack`** (`SECURITY DEFINER`, atômica): valida dono,
  perfil e liga; transfere exatamente as 10 cartas do template associado,
  consome somente pool inicial e é idempotente em chamadas repetidas.
- **Mercado fechado**: `is_market_eligible = false` identifica pool inicial;
  `true` identifica estoque comercial criado por venda de clube.
- **Escopo explícito no mercado**: elenco filtra por `club_id`; vitrine filtra
  por `is_market_eligible = true`. Conta admin não recebe `60/10` nem enxerga
  pool inicial como estoque comercial.
- **RPCs de mercado sistema**: `sell_player_to_system` vende por 50% do valor
  de referência e `buy_player_from_system` compra por 100%, preservando mesma
  carta permanente, ledger e wallet.
- **RPC `train_club_player`**: um treino por clube por dia em `America/Belem`,
  custo por raridade, progresso por carta/atributo e aumento a cada 3 pontos.
- **Ledger imutável**: `wallet_transactions` sem policy de
  INSERT/UPDATE/DELETE para usuário.
- **Domínio TypeScript puro** (`src/domain/`): enums, validadores, OVR,
  improviso, estilo, preços, treino, RNG determinística e calendário.
- **60 jogadores** no catálogo global: 35 peba / 20 paia / 5 pika; 12 GK /
  18 DEF / 18 MID / 12 ATA. OVR e preço são derivados por trigger.
- **66 escudos** em `public/badges/`.
- **PWA** com manifest, ícones e service worker gerado no build.

## Documentação

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- [docs/RULES.md](docs/RULES.md)
- [docs/RLS.md](docs/RLS.md)
- [docs/MARKET.md](docs/MARKET.md)
- [docs/PLAYER_CARDS.md](docs/PLAYER_CARDS.md)
- [docs/SETUP_LOCAL.md](docs/SETUP_LOCAL.md)
- [docs/DEPLOY.md](docs/DEPLOY.md)

## Comandos oficiais

Bun é gerenciador canônico. `bun.lock` é único lockfile versionado. Não rode
`npm install`, `npm ci`, `pnpm` ou `yarn` neste repo.

```bash
bun install --frozen-lockfile
bun run dev
bun run test
bun run test:watch
bun run test:coverage
bun run typecheck
bun run format
bun run format:check
bun run check
bun run check:pwa
bun run assets:players
bun run check:players
bun run build
bun run lint
```

`bun run test` executa Vitest. Evite `bun test`.

`bun run check` valida política de package manager, Prettier, ESLint,
TypeScript, Vitest, PWA, assets de jogadores e build.

Fotos seguem `public/players/<players.code>.webp`, WebP 1024x1024.
`players.name` é nome de display; `players.code` é chave técnica e não aparece
na UI. Detalhes em `docs/PLAYER_CARDS.md`.

## Testes SQL

Testes em `supabase/tests/database/*.sql` não entram no `bun run test`.
Executar manualmente no SQL Editor Lovable, aplicando migration correspondente
e preservando `BEGIN`/`ROLLBACK`.

Pacotes balanceados:

```text
Migration: supabase/migrations/20260713160000_fair_starter_packs.sql
Teste:     supabase/tests/database/fair_starter_packs.sql
Saída:     NOTICE: fair_starter_packs contract test passed
```

Não afirmar que teste SQL passou sem execução no banco.

## PWA

- `lang="pt-BR"`, metadata mobile e manifest ficam no documento principal.
- Assets: `favicon.ico`, `apple-touch-icon.png`, `pwa-192x192.png`,
  `pwa-512x512.png`, `pwa-maskable-192x192.png` e
  `pwa-maskable-512x512.png`.
- Service worker é gerado por `vite-plugin-pwa`, com auto-update e precache
  somente de arquivos estáticos versionados.
- Não há cache dinâmico de Supabase, Auth, RPCs ou dados privados.
- Produção exige HTTPS.

## Auth operacional

- Login usa username + senha. Username vira e-mail interno
  `{username}@bagrefut.local`.
- Confirmação de e-mail deve permanecer desativada no Lovable Cloud Auth.
- Recuperação oficial ocorre via admin com senha temporária.
- Senha temporária define `must_change_password = true`; usuário troca em
  `/trocar-senha` antes de acessar rotas do jogo.

## Pendências principais

- Validar migration e teste SQL dos pacotes no ambiente Lovable Cloud.
- Automatizar testes SQL hoje executados manualmente.
- Envio real de push com VAPID e backend sender.
- Polimento final de UX, observabilidade e operação da beta.
