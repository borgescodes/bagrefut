# Mercado e treino

## Visão geral

A rota autenticada `/mercado` reúne quatro áreas: estoque do sistema, elenco e
treino, anúncios P2P e ofertas de troca. O frontend usa React Query e server
functions autenticadas; as regras críticas permanecem em RPCs Postgres
`SECURITY DEFINER`.

## Mercado do sistema

- A carta é permanente. Compra e venda alteram somente
  `club_players.club_id`; a linha nunca é deletada/recriada.
- `club_id IS NULL` representa posse do sistema e exige uma linha correspondente
  em `system_market_stock`.
- O sistema vende por 100% de `players.reference_value_cents`.
- O sistema compra por `floor(reference_value_cents / 2)`, ou 50%.
- Compra exige saldo suficiente e elenco abaixo de 15 cartas.
- Venda exige que o clube permaneça com pelo menos 5 cartas.
- Toda alteração de saldo passa por `_debit_wallet` ou `_credit_wallet` e cria
  `wallet_transactions` na mesma transação.

## Treino

- Um treino por clube por dia em `America/Belem`.
- Custos: peba 25 cents, paia 75 cents e pika 150 cents.
- Atributos válidos: `velocity`, `finishing`, `passing`, `dribbling`,
  `defending`, `physical` e `goalkeeping`.
- O progresso por carta/atributo é `0 -> 1 -> 2 -> 0`; ao fechar o ciclo o
  atributo recebe `+1` e OVR/preço são recalculados.
- Carta reservada não pode ser treinada.

## Anúncios P2P

- `create_market_listing` aceita preço de 1 a 10.000 cents, valida propriedade,
  reserva, anúncios/ofertas concorrentes e o mínimo de 5 cartas.
- Criar o anúncio e marcar `club_players.is_reserved = true` acontece na mesma
  transação.
- `cancel_market_listing` é idempotente para anúncio já cancelado e libera a
  carta. Anúncio vendido não pode ser cancelado.
- `buy_market_listing` bloqueia anúncio, carta e clubes, revalida saldo e
  elencos, debita o comprador como `market_purchase`, credita o vendedor como
  `market_sale`, transfere a mesma carta e fecha o anúncio como `sold`.
- Reexecução não duplica saldo, ledger ou transferência.

## Ofertas de troca

Semântica:

- `from_club`: clube que cria a oferta.
- `to_club`: clube que recebe e pode aceitar/rejeitar.
- `side = 'from'`: cartas oferecidas pelo criador.
- `side = 'to'`: cartas solicitadas ao destinatário.
- `cash_cents`: dinheiro pago por `from_club` para `to_club`.

Cada lado aceita no máximo 5 cartas, sem duplicação. A oferta precisa conter ao
menos uma carta ou dinheiro, deve expirar no futuro e projetar os dois elencos
entre 5 e 15 cartas. Todas as cartas ficam reservadas enquanto o status é
`pending`.

Aceitar bloqueia oferta, clubes em ordem estável e cartas em ordem UUID. O banco
revalida expiração, propriedade, reserva, saldo e limites antes de transferir
todas as cartas. `cash_cents` usa dois lançamentos `transfer_cash` com
`reference_table = 'transfer_offers'` e o mesmo `reference_id`. Qualquer falha
reverte tudo; não existe transferência parcial.

Aceite, rejeição e cancelamento são idempotentes para o próprio estado final.
`_expire_transfer_offers(now)` muda ofertas vencidas para `expired` e libera as
cartas. O core é executável somente por `postgres`/`service_role` e é chamado
antes das operações públicas que dependem de expiração. Esta migration não cria
novo cron.

## Reserva de carta

`club_players.is_reserved = true` bloqueia venda ao sistema, treino, escalação
manual, escalação automática, novo anúncio, nova oferta e uso simultâneo em
outra negociação. A reserva é criada e liberada dentro da mesma transação que
altera o anúncio ou a oferta.

## Segurança e concorrência

- RPCs públicas validam `auth.uid()`, profile `approved` e clube por `owner_id`;
  nenhum `club_id` do client é usado como autoridade de posse.
- Todas usam `SECURITY DEFINER`, `SET search_path = ''`, referências qualificadas,
  revoke de `PUBLIC`/`anon` e grant somente para `authenticated`.
- Client não escreve diretamente em `market_listings`, `transfer_offers`,
  `transfer_offer_items`, `club_players`, `clubs.balance_cents` ou
  `wallet_transactions`.
- `FOR UPDATE`, ordem estável de locks, índices únicos, revalidação no momento da
  execução e estados idempotentes protegem compras/aceites concorrentes.

## Aplicação manual

1. Faça backup e confirme o ambiente alvo.
2. Aplique `supabase/migrations/20260710120000_usable_market.sql` pelo fluxo de
   migrations do Lovable/Supabase.
3. Em ambiente de teste, execute
   `supabase/tests/database/usable_market.sql` integralmente. O resultado esperado
   termina com `NOTICE: usable_market contract test passed` e `ROLLBACK`.
4. Não execute o teste SQL em um console que remova o `BEGIN`/`ROLLBACK`.

## Regeneração dos tipos Supabase

Os RPCs desta migration usam um helper tipado e Zod até os tipos gerados serem
atualizados. Depois de aplicar a migration, regenere o arquivo sem editar as
assinaturas manualmente:

```powershell
supabase gen types typescript --project-id <PROJECT_ID> --schema public |
  Set-Content -Encoding utf8 src/integrations/supabase/types.ts
```

Em ambiente local já iniciado, use `--local` no lugar de `--project-id`. Depois,
rode `bun run check` e revise o diff de `src/integrations/supabase/types.ts`.
