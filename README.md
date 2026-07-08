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
- **RLS** em todas as 22 tabelas. Nenhum acesso `anon`. Usuário só lê o próprio
  clube, próprias cartas, próprio pacote, próprio ledger e ofertas que o envolvem.
- **Domínio TypeScript puro** (`src/domain/`): enums, tipos, validadores,
  cálculos de OVR, multiplicador de improviso, modificador de estilo, preços de
  referência, RNG determinística (mulberry32) e gerador de tabela de 10 rodadas.
- **32 testes unitários** (Vitest) cobrindo validadores, OVR, multiplicadores,
  preços, RNG determinística e integridade da tabela de rodadas.
- **21 escudos** reais em `public/badges/badge-01.png … badge-21.png`,
  referenciados por `club_badges.asset_path` (caminho portável).
- **60 jogadores** semeados no catálogo global respeitando a distribuição:
  35 peba / 20 paia / 5 pika; 12 GK / 18 DEF / 18 MID / 12 ATA. OVR e preço
  são derivados no Postgres por trigger e os atributos têm variação real por
  posição.
- **Server functions** (`src/lib/*.functions.ts`) como wrappers finos: `getMe`,
  `getMyClub`, `getMyRoster`, `listSystemMarketStock`, `listBadges`,
  `createClub`, `openInitialPack`, `buyPlayerFromSystem`, `sellPlayerToSystem`,
  `trainClubPlayer`, e admin
  (`adminListPendingUsers`, `adminSetUserStatus`, `adminResetUserPassword` —
  service role só no servidor; ação registrada em `admin_audit_logs`).
- **Rotas técnicas**: `/`, `/login`, `/cadastro`, `/aguardando-aprovacao`,
  `/_authenticated/app`, `/_authenticated/criar-clube`, `/_authenticated/abrir-pacote`,
  `/_authenticated/admin`.
- **PWA scaffolding**: `public/manifest.webmanifest`, service worker mínimo
  em `public/sw.js` (registra listeners de Push API — envio real de push
  fica pendente), registro guardado contra dev/preview.

## Documentação

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- [docs/RULES.md](docs/RULES.md)
- [docs/RLS.md](docs/RLS.md)
- [docs/SETUP_LOCAL.md](docs/SETUP_LOCAL.md)
- [docs/DEPLOY.md](docs/DEPLOY.md)

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
- Motor de temporada: `season_start` (gera 10 rodadas + 30 partidas),
  `round_process` (fecha escalações às 21:55, roda simulação, credita prêmios).
- Job `pg_cron` para lock automático de escalação, simulação e revelação de eventos.
- Envio real de push (VAPID keys + backend sender).
- Frontend final com identidade visual, cards de jogador, animação de pacote,
  drag-and-drop de escalação, dashboard, telas de mercado/tabela/histórico.
- Testes de banco em `supabase/tests/database` (pgTAP): sugerido para próxima
  etapa — a fundação já está pronta para receber. Toda regra crítica está no
  Postgres (RLS + RPCs SECURITY DEFINER), então os testes SQL cobrirão o
  contrato real.
- Promoção manual do primeiro admin via SQL — ver `docs/SETUP_LOCAL.md`.
