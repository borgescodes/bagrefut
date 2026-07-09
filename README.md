# BagreFut

**Monte clube. Gerencie elenco. Domine PGM.**

Fundação técnica do projeto. Sem UI final, sem animações, sem drag-and-drop
visual, sem cards de jogador. O que está aqui é: banco correto, regras críticas
no Postgres, RLS, RPCs atômicas, domínio TypeScript puro com testes e telas
técnicas mínimas para operar o backend.

## O que já foi construído

- 24 tabelas em `public/*` cobrindo perfis, papéis, liga, escudos, clubes,
  jogadores, cartas, pacote inicial, temporadas, rodadas, partidas, eventos,
  escalações, treinos, progresso de atributo, estoque do sistema, mercado,
  ofertas de troca, ledger financeiro,
  assinaturas de push e auditoria admin.
- **Saldo por clube** (`clubs.balance_cents`, limitado a R$ 100,00 e nunca
  negativo). Nenhuma policy permite `UPDATE` direto — mutação de saldo só
  via funções internas `_credit_wallet`/`_debit_wallet`, que sempre gravam
  em `wallet_transactions` na mesma transação.
- **RPC `create_club`** (SECURITY DEFINER, atômica): valida autenticação,
  `profiles.status='approved'`, ausência de clube prévio, `leagues.status='setup'`,
  limite de 6 clubes, formato de nome e sigla; cria clube, credita R$ 10,00
  e cria pacote inicial fechado — tudo ou nada.
- **Carta permanente**: `club_players` representa a instância única da carta.
  `club_id IS NOT NULL` significa carta de clube; `club_id IS NULL` significa
  carta no sistema. `system_market_stock` explicita o estoque e o banco valida
  a invariante entre os dois estados.
- **RPC `open_initial_pack`** (SECURITY DEFINER, atômica): valida dono, status
  aprovado, liga em setup, pacote fechado; sorteia 10 cartas somente de
  `system_market_stock`, bloqueia estoque com `FOR UPDATE SKIP LOCKED`, remove
  do estoque e transfere as mesmas cartas para o clube.
- **RPCs de mercado sistema**: `sell_player_to_system` vende ao sistema por 50%
  do valor de referência e `buy_player_from_system` compra do sistema por 100%,
  sempre via transferência atômica da mesma carta permanente, ledger e wallet.
- **RPC `train_club_player`**: um treino por clube por dia em `America/Belem`,
  custo fixo por raridade, progresso persistente por carta/atributo e aumento
  de atributo a cada 3 pontos.
- **Ledger imutável**: `wallet_transactions` sem policy de INSERT/UPDATE/DELETE
  para usuário.
- **RLS** em todas as 24 tabelas. Nenhum acesso `anon`. Usuário só lê o próprio
  clube, próprias cartas, próprio pacote, próprio ledger e ofertas que o envolvem.
- **Domínio TypeScript puro** (`src/domain/`): enums, tipos, validadores,
  cálculos de OVR, multiplicador de improviso, modificador de estilo, preços de
  referência, RNG determinística (mulberry32) e gerador de tabela de 10 rodadas.
- **65 testes unitários** (Vitest) em 8 arquivos, cobrindo auth operacional,
  acesso a eventos de partida, política de package manager, validadores, OVR,
  multiplicadores, preços, treino, RNG determinística e integridade da tabela de rodadas.
- **66 escudos** reais em `public/badges/badge-01.png … badge-66.png`,
  referenciados por `club_badges.asset_path` (caminho portável).
- **60 jogadores** semeados no catálogo global respeitando a distribuição:
  35 peba / 20 paia / 5 pika; 12 GK / 18 DEF / 18 MID / 12 ATA. OVR e preço
  são derivados no Postgres por trigger e os atributos têm variação real por
  posição.
- **Server functions** (`src/lib/*.functions.ts`) como wrappers finos: `getMe`,
  `getMyClub`, `getMyRoster`, `listSystemMarketStock`, `listBadges`,
  `createClub`, `openInitialPack`, `buyPlayerFromSystem`, `sellPlayerToSystem`,
  `trainClubPlayer`, temporada (`getSeasonOperationalState`, `getSeasonStandings`,
  `adminSaveSeasonSetup`, `adminSetSeasonParticipants`, `adminStartSeason`,
  `adminFinishSeason`) e admin
  (`adminListPendingUsers`, `adminSetUserStatus`, `adminResetUserPassword` —
  service role só no servidor; ação registrada em `admin_audit_logs`).
- **Motor operacional de temporada**: admin configura a próxima temporada,
  seleciona exatamente 6 clubes elegíveis, `season_start` gera 10 rodadas e
  30 partidas de forma transacional, o backend expõe rodada atual e
  classificação, e `season_finish` grava campeão, classificação final e
  premiação `season_prize` no ledger uma única vez.
- **Rotas técnicas**: `/`, `/login`, `/cadastro`, `/aguardando-aprovacao`,
  `/_authenticated/app`, `/_authenticated/criar-clube`, `/_authenticated/abrir-pacote`,
  `/_authenticated/admin`.
- **PWA scaffolding**: `public/manifest.webmanifest`, ícones PWA e service
  worker gerado no build por `vite-plugin-pwa`; envio real de push fica pendente.

## Documentação

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- [docs/RULES.md](docs/RULES.md)
- [docs/RLS.md](docs/RLS.md)
- [docs/SETUP_LOCAL.md](docs/SETUP_LOCAL.md)
- [docs/DEPLOY.md](docs/DEPLOY.md)

## Comandos oficiais

Bun e o gerenciador canonico. `bun.lock` e o unico lockfile versionado; nao
rode `npm install`, `npm ci`, `pnpm` ou `yarn` neste repo. Os scripts tambem
aceitam `npm run <script>` quando `node_modules` ja estiver instalado, mas npm
nao e usado para instalar dependencias.

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
bun run build
bun run lint
```

`bun run test` executa Vitest. Evite `bun test`, porque este repo nao usa o
runner nativo do Bun para a suite TS.

`bun run format` aplica Prettier. `bun run format:check` valida Prettier sem
alterar arquivos.

`bun run check` valida, nesta ordem: politica de package manager, Prettier,
ESLint, TypeScript, Vitest, assets/manifest PWA e build.

O repo usa LF como fim de linha padrao via `.gitattributes`. Arquivos `.bat`,
`.cmd` e `.ps1` permanecem CRLF; imagens, favicon, fontes e ZIPs sao binarios.

## PWA

- `lang="pt-BR"`, metadata mobile e manifest ficam no documento principal.
- `public/manifest.webmanifest` declara `name`, `short_name`, `description`,
  `lang`, `start_url`, `scope`, `display`, `orientation`, cores e icones.
- Assets do app: `favicon.ico`, `apple-touch-icon.png`, `pwa-192x192.png`,
  `pwa-512x512.png`, `pwa-maskable-192x192.png` e `pwa-maskable-512x512.png`.
- O service worker e gerado no build por `vite-plugin-pwa`, com auto-update e
  precache apenas de arquivos estaticos versionados em `.output/public`.
- Nao ha cache dinamico de Supabase, Auth, RPCs ou dados privados, e o app nao
  promete suporte offline total.
- Para testar instalacao local, rode `bun run build`, `bun run preview`, abra a
  URL de preview, confira `/manifest.webmanifest`, `/sw.js` e os icones. Em
  producao, instalacao PWA exige HTTPS; Lovable deve servir manifest, icones e
  service worker no mesmo escopo `/`.

Testes SQL em `supabase/tests/database/*.sql` nao entram no `bun run test`.
Existem 7 testes SQL transacionais:

- `admin_audit_and_game_rls.sql`
- `club_identity_security.sql`
- `match_events_rls.sql`
- `open_initial_pack_concurrency.sql`
- `player_market_training.sql`
- `save_lineup_security.sql`
- `season_engine.sql`

Eles cobrem RLS, acesso admin, usuário comum/pending/blocked, isolamento por
clube/owner, saldo e ledger, compra/venda, treino diário, escalação e leitura
protegida de eventos/resultados. Rodam manualmente no SQL Editor Lovable, sempre
aplicando a migration correspondente antes do teste SQL. Preserve `BEGIN` /
`ROLLBACK` na execucao manual. Nao trate esses testes como parte do Vitest nem
afirme que passaram sem execucao no banco.

## Partidas e eventos

- `listMatchSummaries`, `getMatchDetails` e `getMatchEvents` mantem contratos
  separados para placar/resumo, detalhe e minuto a minuto.
- `list_match_score_summaries` expoe somente colunas de resumo: partida,
  status, rodada, competicao, data, clubes, escudos, placar e resultado final.
- Eventos completos em `match_events` sao visiveis somente para admin approved
  ou usuario approved cujo clube seja mandante/visitante.
- Usuarios approved estranhos veem apenas placar/resumo. Pending, blocked e anon
  nao veem resumo nem eventos.
- `reveal_at`, data passada e partida encerrada nao liberam eventos completos.
- O client nao escreve diretamente em `match_events`; escrita fica restrita ao
  backend confiavel/service role ou RPC administrativa existente.
- A migration `supabase/migrations/20260708120000_match_events_rls.sql` deve ser
  aplicada manualmente no SQL Editor Lovable.

## Auth operacional

- O login usa username + senha. O username é convertido para e-mail interno
  `{username}@bagrefut.local`; esses e-mails não são entregáveis e não aparecem
  no fluxo do usuário.
- No Lovable Cloud Auth, a confirmação de e-mail deve permanecer desativada.
  Recuperação por e-mail não deve ser usada.
- A recuperação oficial é via WhatsApp com solicitação ao admin, seguida de
  geração de senha temporária no painel administrativo.
- Senha temporária marca `auth.users.app_metadata.must_change_password = true`.
  O usuário deve trocar a senha em `/trocar-senha` antes de acessar rotas do jogo.
- Depois de alterar qualquer configuração de Auth no Lovable Cloud, valide
  cadastro e login manualmente.

## O que ficou pendente

- Simulação minuto-a-minuto real (motor, geração de `match_events`, tempo-real).
- Mercado P2P (`market_listings`) e ofertas/preço entre clubes.
- RPCs de troca (`transfer_offer_create`, `transfer_offer_accept`, `transfer_offer_reject`).
- Simulação de partidas e `round_process` automático (fecha escalações, gera
  placares/eventos e revela resultados).
- Job `pg_cron` para lock automático de escalação, simulação e revelação de eventos.
- Envio real de push (VAPID keys + backend sender).
- Frontend final com identidade visual, cards de jogador, animação de pacote,
  drag-and-drop de escalação, dashboard, telas de mercado/tabela/histórico.
- Automacao local dos testes SQL. Hoje eles existem em `supabase/tests/database`
  e sao executados manualmente no SQL Editor Lovable, com rollback.
- Promoção manual do primeiro admin via SQL — ver `docs/SETUP_LOCAL.md`.
