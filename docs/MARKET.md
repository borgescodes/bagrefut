# Mercado e treino

## Visão geral

A rota autenticada `/mercado` reúne quatro áreas:

1. `Meu elenco`: cartas do próprio clube, treino e venda ao sistema.
2. `Sistema`: vitrine formada somente por cartas vendidas por clubes.
3. `P2P`: anúncios de preço fixo entre clubes.
4. `Trocas`: ofertas diretas com cartas e dinheiro.

Frontend usa React Query e server functions autenticadas. Regras críticas ficam nas RPCs
Postgres `SECURITY DEFINER`.

## Contrato econômico

- Catálogo fechado: 60 jogadores únicos.
- Seis clubes recebem 10 cartas cada no pacote inicial.
- Pacotes são pré-definidos, balanceados e exclusivos.
- Elenco mínimo: 5 cartas.
- Elenco máximo: 10 cartas.
- Saldo máximo do clube: 99.999 cents (`R$ 999,99`).
- Preço máximo por carta: 10.000 cents (`R$ 100,00`).
- Dinheiro máximo por anúncio/oferta: 10.000 cents (`R$ 100,00`).

## Pacotes iniciais

`starter_pack_templates` guarda seis composições fixas, `PACK01` a `PACK06`.
Cada template possui exatamente 10 jogadores: 2 GK, 3 DEF, 3 MID e 2 ATA.

`initial_packs.starter_pack_template_id` associa um template exclusivo ao clube.
A atribuição ocorre aleatoriamente entre templates livres dentro da transação de
`create_club`. A constraint `UNIQUE` impede dois clubes de receberem o mesmo pacote.

`open_initial_pack` não sorteia cartas soltas. A RPC transfere exatamente os 10 jogadores
do template associado, preserva slots e retorna os mesmos itens quando chamada novamente.

## Pool inicial e vitrine do sistema

`system_market_stock` possui dois estados:

- `is_market_eligible = false`: pool reservado aos pacotes iniciais; não aparece na UI e
  não pode ser comprado.
- `is_market_eligible = true`: carta vendida por um clube; aparece na vitrine e pode ser
  comprada.

A vitrine começa vazia. Não existe estoque comercial inicial.

Abrir pacote consome apenas cartas com `is_market_eligible = false`. Comprar do sistema
consome apenas cartas com `is_market_eligible = true`.

## Compra e venda ao sistema

A carta é permanente. Compra e venda alteram somente `club_players.club_id`; a linha não
é deletada/recriada.

- Sistema compra do clube por `floor(reference_value_cents / 2)`, ou 50%.
- Sistema vende ao clube por 100% de `players.reference_value_cents`.
- Compra exige saldo suficiente e elenco abaixo de 10 cartas.
- Venda exige que o clube permaneça com pelo menos 5 cartas.
- Venda é bloqueada se o crédito ultrapassar `R$ 999,99`.
- Toda mutação de saldo passa por `_debit_wallet` ou `_credit_wallet` e grava
  `wallet_transactions` na mesma transação.

## Posse e escopo de consulta

`Meu elenco` aplica filtro funcional explícito:

```ts
.eq("club_id", clubId)
```

A tela não depende somente da RLS para definir escopo. Isso impede conta admin de receber
cartas de outros clubes ou do sistema no contador do próprio elenco.

A vitrine do sistema também aplica filtro explícito:

```ts
.eq("is_market_eligible", true)
```

Pool inicial permanece invisível mesmo quando a conta possui papel admin.

Usuário pode treinar, vender, anunciar ou oferecer somente carta própria. Carta de outro
clube aparece apenas:

- em anúncio P2P, para compra;
- na criação de troca, como carta solicitada.

RPCs revalidam `auth.uid()`, profile `approved`, propriedade, reservas, saldo e limites.
Nenhum `club_id` recebido do client é autoridade de posse.

## Treino

- Um treino por clube por dia em `America/Belem`.
- Custos: peba 25 cents, paia 75 cents e pika 150 cents.
- Atributos válidos: `velocity`, `finishing`, `passing`, `dribbling`, `defending`,
  `physical` e `goalkeeping`.
- Progresso por carta/atributo: `0 -> 1 -> 2 -> 0`.
- Ao fechar ciclo, atributo recebe `+1`; OVR e valor de referência são recalculados.
- Carta reservada não pode ser treinada.

## Anúncios P2P

- Preço permitido: 1 a 10.000 cents.
- Criar anúncio reserva a carta na mesma transação.
- Cancelar anúncio libera a carta.
- Comprar transfere carta e saldo atomicamente.
- Comprador precisa terminar com no máximo 10 cartas.
- Vendedor precisa terminar com no mínimo 5 cartas.
- Vendedor não pode receber crédito que ultrapasse `R$ 999,99`.
- Reexecução não duplica saldo, ledger ou transferência.

## Ofertas de troca

Semântica:

- `from_club`: clube que cria a oferta.
- `to_club`: clube que recebe e pode aceitar/rejeitar.
- `side = 'from'`: cartas oferecidas pelo criador.
- `side = 'to'`: cartas solicitadas ao destinatário.
- `cash_cents`: dinheiro pago por `from_club` para `to_club`.

Cada lado aceita no máximo 5 cartas. Oferta precisa conter carta ou dinheiro, expirar no
futuro e projetar ambos os elencos entre 5 e 10 cartas. Dinheiro máximo: `R$ 100,00`.

Todas as cartas ficam reservadas enquanto status é `pending`. Aceite transfere tudo ou
reverte tudo; não existe transferência parcial.

## Reserva de carta

`club_players.is_reserved = true` bloqueia:

- venda ao sistema;
- treino;
- escalação;
- novo anúncio;
- nova oferta;
- uso simultâneo em outra negociação.

Reserva é criada/liberada dentro da mesma transação que altera anúncio ou oferta.

## UI

Cartas usam o componente compartilhado `PlayerCard`.

- imagem: `/players/<players.code>.webp`;
- nome: `players.name`;
- setor: formatado somente para display;
- fallback visual usa nome e posição, sem exibir código técnico;
- controles de treino/venda aparecem somente em `Meu elenco`;
- vitrine vazia explica que estoque nasce das vendas dos clubes.

## Migrations e testes

Contrato fechado e pacotes balanceados:

- `supabase/migrations/20260710190000_closed_market_economy.sql`;
- `supabase/migrations/20260710191000_fix_closed_market_ambiguity.sql`;
- `supabase/migrations/20260713160000_fair_starter_packs.sql`;
- `supabase/tests/database/closed_market_economy.sql`;
- `supabase/tests/database/fair_starter_packs.sql`.

Teste novo deve terminar com:

```text
NOTICE: fair_starter_packs contract test passed
ROLLBACK
```

Não executar teste em console que remova `BEGIN`/`ROLLBACK`.
