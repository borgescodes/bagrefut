# BagreFut

**Monte clube. Gerencie elenco. Domine PGM.**

Fundação técnica do projeto. Sem UI final, sem animações, sem drag-and-drop
visual, sem cards de jogador. O que está aqui é: banco correto, regras críticas
no Postgres, RLS, RPCs atômicas, domínio TypeScript puro com testes e telas
técnicas mínimas para operar o backend.

## O que já foi construído

- 26 tabelas em `public/*` cobrindo perfis, papéis, liga, escudos, clubes,
  jogadores, cartas, templates de pacote inicial, temporadas, rodadas,
  partidas, eventos, escalações, treinos, progresso de atributo, estoque do
  sistema, mercado, ofertas de troca, ledger financeiro, assinaturas de push
  e auditoria admin.
- **Saldo por clube** (`clubs.balance_cents`, limitado a R$ 999,99 e nunca
  negativo). Nenhuma policy permite `UPDATE` direto - mutação de saldo só
  via funções internas `_credit_wallet`/`_debit_wallet`, que sempre gravam
  em `wallet_transactions` na mesma transação.
- **RPC `create_club`** (`SECURITY DEFINER`, atômica): valida autenticação,
  `profiles.status='approved'`, ausência de clube prévio, `leagues.status='setup'`,
  limite de 6 clubes, formato de nome e sigla; cria clube, credita R$ 10,00,
  reserva um dos 6 templates livres e cria pacote inicial fechado - tudo ou nada.
- **Seis pacotes iniciais balanceados**: `PACK01` a `PACK06`, cada um com 10
  cartas, sendo 2 GK, 3 DEF, 3 MID e 2 ATA. Cada jogador aparece em somente um
  template; cada template pode pertencer a somente um clube.
- **Carta permanente**: `club_players` representa instância única da carta.
  `club_id IS NOT NULL` significa carta de clube; `club_id IS NULL` significa
  carta no sistema. `system_market_stock` explicita estoque e banco valida
  invariante entre os dois estados.
- **RPC `open_initial_pack`** (`SECURITY DEFINER`, atômica): valida dono, status
  aprovado, liga em setup e pacote; transfere exatamente as 10 cartas do
  template associado, consome somente pool inicial e retorna os mesmos itens
  em chamadas repetidas.
- **Escopo explícito no mercado**: elenco filtra `club_players.club_id` pelo
  clube autenticado e vitrine filtra `system_market_stock.is_market_eligible = true`.
  Conta admin não recebe cartas de outros clubes no contador `Elenco x/10`.
- **RPCs de mercado sistema**: `sell_player_to_system` vende ao sistema por 50%
  do valor de referência e `buy_player_from_system` compra do sistema por 100%,
  sempre via transferência atômica da mesma carta permanente, ledger e wallet.
- **RPC `train_club_player`**: um treino por clube por dia em `America/Belem`,
  custo fixo por raridade, progresso persistente por carta/atributo e aumento
  de atributo a cada 3 pontos.
- **Ledger imutável**: `wallet_transactions` sem policy de INSERT/UPDATE/DELETE
  para usuário.
- **RLS** nas tabelas públicas. Nenhum acesso `anon`. Usuário só lê próprio
  clube, próprias cartas, próprio pacote, próprio ledger e ofertas que o envolvem;
  admin mantém acesso operacional ampliado sem alterar escopo funcional das telas.
- **Domínio TypeScript puro** (`src/domain/`): enums, tipos, validadores,
  cálculos de OVR, multiplicador de improviso, modificador de estilo, preços de
  referência, RNG determinística (mulberry32) e gerador de tabela de 10 rodadas.
- **Testes unitários Vitest** cobrindo auth operacional, acesso a eventos,
  política de package manager, validadores, OVR, multiplicadores, preços,
  treino, RNG, mercado e integridade da tabela de rodadas.
- **66 escudos** reais em `public/badges/badge-01.png ... badge-66.png`,
  referenciados por `club_badges.asset_path`.
- **60 jogadores** semeados no catálogo global respeitando distribuição:
  35 peba / 20 paia / 5 pika; 12 GK / 18 DEF / 18 MID / 12 ATA. OVR e preço
  são derivados no Postgres por trigger e atributos têm variação por posição.
- **Server functions** (`src/lib/*.functions.ts`) como wrappers finos: `getMe`,
  `getMyClub`, `getMyRoster`, `listSystemMarketStock`, `listBadges`,
  `createClub`, `openInitialPack`, `buyPlayerFromSystem`, `sellPlayerToSystem`,
  `trainClubPlayer`, temporada (`getSeasonOperationalState`, `getSeasonStandings`,
  `adminSaveSeasonSetup`, `adminSetSeasonParticipants`, `adminStartSeason`,
  `adminFinishSeason`) e admin
  (`adminListPendingUsers`, `adminSetUserStatus`, `adminResetUserPassword` -
  service role só no servidor; ação registrada em `admin_audit_logs`).
- **Motor operacional de temporada**: admin configura próxima temporada,
  seleciona exatamente 6 clubes elegíveis, `season_start` gera 10 rodadas e
  30 partidas de forma transacional, backend expõe rodada atual e
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
- [docs/MARKET.md](docs/MARKET.md)
- [docs/PLAYER_CARDS.md](docs/PLAYER_CARDS.md)
- [docs/SETUP_LOCAL.md](docs/SETUP_LOCAL.md)
- [docs/DEPLOY.md](docs/DEPLOY.md)

## Comandos oficiais

Bun é gerenciador canônico. `bun.lock` é único lockfile versionado; não
rode `npm install`, `npm ci`, `pnpm` ou `yarn` neste repo. Scripts também
aceitam `npm run <script>` quando `node_modules` já estiver instalado, mas npm
não é usado para instalar dependências.

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

`bun run test` executa Vitest. Evite `bun test`, porque repo não usa runner
nativo do Bun para suíte TS.

`bun run format` aplica Prettier. `bun run format:check` valida Prettier sem
alterar arquivos.

`bun run check` valida, nesta ordem: política de package manager, Prettier,
ESLint, TypeScript, Vitest, assets/manifest PWA, assets de jogadores e build.

Fotos de jogadores seguem contrato `public/players/<players.code>.webp`
(ex.: `public/players/ATA12.webp`) - WebP 1024x1024. `players.name` é nome
de display; `players.code` é chave técnica e nunca aparece na UI. Jogadores
sem foto usam fallback por nome. Pipeline: `bun run assets:players`; validação:
`bun run check:players`. Detalhes em `docs/PLAYER_CARDS.md`.

Repo usa LF como fim de linha padrão via `.gitattributes`. Arquivos `.bat`,
`.cmd` e `.ps1` permanecem CRLF; imagens, favicon, fontes e ZIPs são binários.

## PWA

- `lang="pt-BR"`, metadata mobile e manifest ficam no documento principal.
- `public/manifest.webmanifest` declara `name`, `short_name`, `description`,
  `lang`, `start_url`, `scope`, `display`, `orientation`, cores e ícones.
- Assets do app: `favicon.ico`, `apple-touch-icon.png`, `pwa-192x192.png`,
  `pwa-512x512.png`, `pwa-maskable-192x192.png` e `pwa-maskable-512x512.png`.
- Service worker é gerado no build por `vite-plugin-pwa`, com auto-update e
  precache apenas de arquivos estáticos versionados em `.output/public`.
- Não há cache dinâmico de Supabase, Auth, RPCs ou dados privados, e app não
  promete suporte offline total.
- Para testar instalação local, rode `bun run build`, `bun run preview`, abra
  URL de preview, confira `/manifest.webmanifest`, `/sw.js` e ícones. Em
  produção, instalação PWA exige HTTPS.

Testes SQL em `supabase/tests/database/*.sql` não entram no `bun run test`.
Rodam manualmente no SQL Editor Lovable, sempre aplicando migration
correspondente antes do teste e preservando `BEGIN`/`ROLLBACK`.

Pacotes balanceados:

```text
Migration: supabase/migrations/20260713160000_fair_starter_packs.sql
Teste:     supabase/tests/database/fair_starter_packs.sql
Saída:     NOTICE: fair_starter_packs contract test passed
```

Não afirmar que testes SQL passaram sem execução no banco.

## Partidas e eventos

- `listMatchSummaries`, `getMatchDetails` e `getMatchEvents` mantêm contratos
  separados para placar/resumo, detalhe e minuto a minuto.
- `list_match_score_summaries` expõe somente colunas de resumo: partida,
  status, rodada, competição, data, clubes, escudos, placar e resultado final.
- Eventos completos em `match_events` são visíveis somente para admin approved
  ou usuário approved cujo clube seja mandante/visitante.
- Usuários approved estranhos veem apenas placar/resumo. Pending, blocked e anon
  não veem resumo nem eventos.
- `reveal_at`, data passada e partida encerrada não liberam eventos completos.
- Client não escreve diretamente em `match_events`; escrita fica restrita ao
  backend confiável/service role ou RPC administrativa existente.

## Auth operacional

- Login usa username + senha. Username é convertido para e-mail interno
  `{username}@bagrefut.local`; esses e-mails não são entregáveis e não aparecem
  no fluxo do usuário.
- No Lovable Cloud Auth, confirmação de e-mail deve permanecer desativada.
  Recuperação por e-mail não deve ser usada.
- Recuperação oficial é via WhatsApp com solicitação ao admin, seguida de
  geração de senha temporária no painel administrativo.
- Senha temporária marca `auth.users.app_metadata.must_change_password = true`.
  Usuário deve trocar senha em `/trocar-senha` antes de acessar rotas do jogo.
- Depois de alterar configuração de Auth no Lovable Cloud, valide cadastro e
  login manualmente.

## O que ficou pendente

- Executar migration e teste SQL dos pacotes no ambiente Lovable Cloud.
- Automatizar testes SQL hoje executados manualmente.
- Envio real de push (VAPID keys + backend sender).
- Promoção manual do primeiro admin via SQL - ver `docs/SETUP_LOCAL.md`.
