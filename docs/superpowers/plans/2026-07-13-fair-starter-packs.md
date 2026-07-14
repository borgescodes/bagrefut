# Fair Starter Packs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Substituir sorteio de cartas soltas por 6 pacotes iniciais fechados e exclusivos, corrigindo também elenco `60/10` e exposição do pool inicial no mercado admin.

**Architecture:** Migration forward-only cria templates privados, semeia 60 cartas, faz backfill aleatório e redefine `create_club`/`open_initial_pack`. Server functions filtram explicitamente clube e estoque comercial, sem usar amplitude da RLS como regra funcional.

**Tech Stack:** PostgreSQL/Supabase, PL/pgSQL, TanStack Start, TypeScript, Supabase JS, Zod, Vitest, Bun.

## Global Constraints

- Produção: exatamente `PACK01` a `PACK06`.
- Cada pacote: 10 cartas, sendo 2 GK, 3 DEF, 3 MID, 2 ATA.
- Cada jogador pertence a um único template.
- Cada template pertence a no máximo um clube.
- Atribuição aleatória entre templates livres.
- Abertura determinística pelo template.
- Estoque comercial nunca entra em pacote.
- Reabertura idempotente.
- Migration nova; migrations antigas intactas.
- Admin vê somente próprio elenco e estoque comercial.
- Bun canônico; usar `bun run`, nunca `bun test`.

---

## File Map

- Create: `supabase/migrations/20260713160000_fair_starter_packs.sql`
- Create: `supabase/tests/database/fair_starter_packs.sql`
- Modify: `supabase/tests/database/open_initial_pack_concurrency.sql`
- Modify: `supabase/tests/database/closed_market_economy.sql`
- Modify: `src/lib/market.functions.ts`
- Create: `src/test/market-functions.test.ts`
- Modify: `src/integrations/supabase/types.ts`
- Modify: `README.md`
- Modify: `docs/RULES.md`
- Modify: `docs/PLAYER_CARDS.md`
- Modify: `docs/MARKET.md`
- Modify: `docs/SETUP_LOCAL.md`

---

### Task 1: Criar teste SQL vermelho

**Files:**
- Create: `supabase/tests/database/fair_starter_packs.sql`

**Interfaces:**
- Consumes: novas tabelas e FK.
- Produces: NOTICE `fair_starter_packs contract test passed`.

- [ ] **Step 1: Escrever contrato estrutural**

```sql
BEGIN;

DO $$
DECLARE
  _expected jsonb := jsonb_build_object(
    'PACK01', jsonb_build_array('GK05','GK11','DEF11','DEF09','DEF03','MID04','MID14','MID13','ATA01','ATA12'),
    'PACK02', jsonb_build_array('GK01','GK03','DEF05','DEF02','DEF16','MID08','MID09','MID18','ATA07','ATA08'),
    'PACK03', jsonb_build_array('GK02','GK12','DEF10','DEF14','DEF13','MID05','MID06','MID15','ATA04','ATA03'),
    'PACK04', jsonb_build_array('GK06','GK09','DEF07','DEF08','DEF18','MID07','MID02','MID12','ATA06','ATA09'),
    'PACK05', jsonb_build_array('GK07','GK10','DEF01','DEF17','DEF12','MID10','MID03','MID17','ATA02','ATA11'),
    'PACK06', jsonb_build_array('GK04','GK08','DEF04','DEF06','DEF15','MID01','MID11','MID16','ATA05','ATA10')
  );
  _code text;
  _actual jsonb;
BEGIN
  IF (SELECT count(*) FROM public.starter_pack_templates WHERE code ~ '^PACK0[1-6]$') <> 6 THEN
    RAISE EXCEPTION 'assertion_failed: production templates';
  END IF;

  IF (
    SELECT count(*)
    FROM public.starter_pack_template_items i
    JOIN public.starter_pack_templates t ON t.id = i.template_id
    WHERE t.code ~ '^PACK0[1-6]$'
  ) <> 60 THEN
    RAISE EXCEPTION 'assertion_failed: production items';
  END IF;

  IF (
    SELECT count(DISTINCT i.player_id)
    FROM public.starter_pack_template_items i
    JOIN public.starter_pack_templates t ON t.id = i.template_id
    WHERE t.code ~ '^PACK0[1-6]$'
  ) <> 60 THEN
    RAISE EXCEPTION 'assertion_failed: duplicated player';
  END IF;

  FOR _code IN SELECT jsonb_object_keys(_expected) LOOP
    SELECT jsonb_agg(p.code ORDER BY i.slot)
    INTO _actual
    FROM public.starter_pack_templates t
    JOIN public.starter_pack_template_items i ON i.template_id = t.id
    JOIN public.players p ON p.id = i.player_id
    WHERE t.code = _code;

    IF _actual <> _expected -> _code THEN
      RAISE EXCEPTION 'assertion_failed: composition %', _code;
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM public.starter_pack_templates t
    JOIN public.starter_pack_template_items i ON i.template_id = t.id
    JOIN public.players p ON p.id = i.player_id
    WHERE t.code ~ '^PACK0[1-6]$'
    GROUP BY t.id
    HAVING count(*) <> 10
       OR count(*) FILTER (WHERE p.position = 'GK') <> 2
       OR count(*) FILTER (WHERE p.position = 'DEF') <> 3
       OR count(*) FILTER (WHERE p.position = 'MID') <> 3
       OR count(*) FILTER (WHERE p.position = 'ATA') <> 2
       OR sum(p.overall) <> t.expected_total_overall
  ) THEN
    RAISE EXCEPTION 'assertion_failed: shape or OVR';
  END IF;

  IF EXISTS (
    SELECT starter_pack_template_id
    FROM public.initial_packs
    GROUP BY starter_pack_template_id
    HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'assertion_failed: repeated assignment';
  END IF;

  RAISE NOTICE 'fair_starter_packs contract test passed';
END;
$$;

ROLLBACK;
```

- [ ] **Step 2: Confirmar falha inicial**

Run: SQL Editor.

Expected: `relation "public.starter_pack_templates" does not exist`.

- [ ] **Step 3: Commit**

```bash
git add supabase/tests/database/fair_starter_packs.sql
git commit -m "test: definir contrato dos pacotes iniciais"
```

---

### Task 2: Implementar migration e RPCs

**Files:**
- Create: `supabase/migrations/20260713160000_fair_starter_packs.sql`

**Interfaces:**
- Produces: `starter_pack_templates`, `starter_pack_template_items`.
- Produces: `initial_packs.starter_pack_template_id uuid not null unique`.
- Preserva assinatura de `create_club` e `open_initial_pack`.

- [ ] **Step 1: Preflight antes do DDL**

```sql
DO $$
DECLARE
  _codes text[] := ARRAY[
    'GK05','GK11','DEF11','DEF09','DEF03','MID04','MID14','MID13','ATA01','ATA12',
    'GK01','GK03','DEF05','DEF02','DEF16','MID08','MID09','MID18','ATA07','ATA08',
    'GK02','GK12','DEF10','DEF14','DEF13','MID05','MID06','MID15','ATA04','ATA03',
    'GK06','GK09','DEF07','DEF08','DEF18','MID07','MID02','MID12','ATA06','ATA09',
    'GK07','GK10','DEF01','DEF17','DEF12','MID10','MID03','MID17','ATA02','ATA11',
    'GK04','GK08','DEF04','DEF06','DEF15','MID01','MID11','MID16','ATA05','ATA10'
  ];
BEGIN
  IF (SELECT count(*) FROM public.clubs) > 6 THEN
    RAISE EXCEPTION 'fair_starter_packs_more_than_six_clubs';
  END IF;
  IF EXISTS (SELECT 1 FROM public.initial_packs WHERE opened_at IS NOT NULL) THEN
    RAISE EXCEPTION 'fair_starter_packs_opened_pack_exists';
  END IF;
  IF EXISTS (SELECT 1 FROM public.club_players WHERE club_id IS NOT NULL) THEN
    RAISE EXCEPTION 'fair_starter_packs_owned_card_exists';
  END IF;
  IF cardinality(_codes) <> 60
     OR (SELECT count(DISTINCT x) FROM unnest(_codes) AS x) <> 60 THEN
    RAISE EXCEPTION 'fair_starter_packs_invalid_definition';
  END IF;
  IF (SELECT count(*) FROM public.players WHERE code = ANY(_codes)) <> 60 THEN
    RAISE EXCEPTION 'fair_starter_packs_player_code_missing';
  END IF;
  IF (
    SELECT count(*)
    FROM public.players p
    JOIN public.club_players cp ON cp.player_id = p.id
    JOIN public.system_market_stock sms ON sms.club_player_id = cp.id
    WHERE p.code = ANY(_codes)
      AND cp.club_id IS NULL
      AND NOT cp.is_reserved
      AND NOT sms.is_market_eligible
  ) <> 60 THEN
    RAISE EXCEPTION 'fair_starter_packs_card_not_in_initial_pool';
  END IF;
  IF (SELECT sum(overall) FROM public.players WHERE code = ANY(ARRAY['GK05','GK11','DEF11','DEF09','DEF03','MID04','MID14','MID13','ATA01','ATA12'])) <> 579
     OR (SELECT sum(overall) FROM public.players WHERE code = ANY(ARRAY['GK01','GK03','DEF05','DEF02','DEF16','MID08','MID09','MID18','ATA07','ATA08'])) <> 578
     OR (SELECT sum(overall) FROM public.players WHERE code = ANY(ARRAY['GK02','GK12','DEF10','DEF14','DEF13','MID05','MID06','MID15','ATA04','ATA03'])) <> 579
     OR (SELECT sum(overall) FROM public.players WHERE code = ANY(ARRAY['GK06','GK09','DEF07','DEF08','DEF18','MID07','MID02','MID12','ATA06','ATA09'])) <> 579
     OR (SELECT sum(overall) FROM public.players WHERE code = ANY(ARRAY['GK07','GK10','DEF01','DEF17','DEF12','MID10','MID03','MID17','ATA02','ATA11'])) <> 578
     OR (SELECT sum(overall) FROM public.players WHERE code = ANY(ARRAY['GK04','GK08','DEF04','DEF06','DEF15','MID01','MID11','MID16','ATA05','ATA10'])) <> 579 THEN
    RAISE EXCEPTION 'fair_starter_packs_overall_mismatch';
  END IF;
END;
$$;
```

- [ ] **Step 2: Criar schema privado**

```sql
CREATE TABLE public.starter_pack_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE CHECK (code ~ '^[A-Z0-9_]{4,16}$'),
  expected_total_overall smallint NOT NULL,
  expected_starter_overall smallint NOT NULL,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.now()
);

CREATE TABLE public.starter_pack_template_items (
  template_id uuid NOT NULL REFERENCES public.starter_pack_templates(id) ON DELETE CASCADE,
  player_id uuid NOT NULL REFERENCES public.players(id) ON DELETE RESTRICT,
  slot smallint NOT NULL CHECK (slot BETWEEN 1 AND 10),
  PRIMARY KEY (template_id, slot),
  UNIQUE (player_id)
);

GRANT ALL ON public.starter_pack_templates TO service_role;
GRANT ALL ON public.starter_pack_template_items TO service_role;
REVOKE ALL ON public.starter_pack_templates FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.starter_pack_template_items FROM PUBLIC, anon, authenticated;
ALTER TABLE public.starter_pack_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.starter_pack_template_items ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.initial_packs
  ADD COLUMN starter_pack_template_id uuid NULL
  REFERENCES public.starter_pack_templates(id) ON DELETE RESTRICT;
ALTER TABLE public.initial_packs
  ADD CONSTRAINT initial_packs_starter_template_unique UNIQUE (starter_pack_template_id);
```

- [ ] **Step 3: Seed exato**

```sql
WITH definitions(code, total, starter, player_codes) AS (
  VALUES
    ('PACK01',579::smallint,335::smallint,ARRAY['GK05','GK11','DEF11','DEF09','DEF03','MID04','MID14','MID13','ATA01','ATA12']::text[]),
    ('PACK02',578::smallint,335::smallint,ARRAY['GK01','GK03','DEF05','DEF02','DEF16','MID08','MID09','MID18','ATA07','ATA08']::text[]),
    ('PACK03',579::smallint,336::smallint,ARRAY['GK02','GK12','DEF10','DEF14','DEF13','MID05','MID06','MID15','ATA04','ATA03']::text[]),
    ('PACK04',579::smallint,336::smallint,ARRAY['GK06','GK09','DEF07','DEF08','DEF18','MID07','MID02','MID12','ATA06','ATA09']::text[]),
    ('PACK05',578::smallint,336::smallint,ARRAY['GK07','GK10','DEF01','DEF17','DEF12','MID10','MID03','MID17','ATA02','ATA11']::text[]),
    ('PACK06',579::smallint,336::smallint,ARRAY['GK04','GK08','DEF04','DEF06','DEF15','MID01','MID11','MID16','ATA05','ATA10']::text[])
), inserted AS (
  INSERT INTO public.starter_pack_templates(code, expected_total_overall, expected_starter_overall)
  SELECT code, total, starter FROM definitions
  RETURNING id, code
)
INSERT INTO public.starter_pack_template_items(template_id, player_id, slot)
SELECT t.id, p.id, u.slot::smallint
FROM definitions d
JOIN inserted t USING (code)
CROSS JOIN LATERAL unnest(d.player_codes) WITH ORDINALITY AS u(player_code, slot)
JOIN public.players p ON p.code = u.player_code;
```

- [ ] **Step 4: Backfill e NOT NULL**

```sql
WITH packs AS (
  SELECT id, row_number() OVER (ORDER BY pg_catalog.random(), id) rn
  FROM public.initial_packs
), templates AS (
  SELECT id, row_number() OVER (ORDER BY pg_catalog.random(), id) rn
  FROM public.starter_pack_templates
  WHERE code ~ '^PACK0[1-6]$'
)
UPDATE public.initial_packs ip
SET starter_pack_template_id = t.id
FROM packs p
JOIN templates t USING (rn)
WHERE ip.id = p.id;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.initial_packs WHERE starter_pack_template_id IS NULL) THEN
    RAISE EXCEPTION 'fair_starter_packs_backfill_failed';
  END IF;
END;
$$;

ALTER TABLE public.initial_packs ALTER COLUMN starter_pack_template_id SET NOT NULL;
```

- [ ] **Step 5: Atualizar `create_club`**

Copiar função vigente de `20260707214653_fix_club_identity_and_badges.sql`. Adicionar variável `_starter_pack_template_id uuid` e, antes do insert de clube:

```sql
SELECT t.id INTO _starter_pack_template_id
FROM public.starter_pack_templates t
WHERE t.code LIKE 'PACK%'
  AND NOT EXISTS (
    SELECT 1 FROM public.initial_packs ip
    WHERE ip.starter_pack_template_id = t.id
  )
ORDER BY pg_catalog.random(), t.id
LIMIT 1
FOR UPDATE SKIP LOCKED;

IF _starter_pack_template_id IS NULL THEN
  RAISE EXCEPTION 'starter_pack_templates_exhausted';
END IF;
```

Trocar criação de pacote por:

```sql
INSERT INTO public.initial_packs(club_id, starter_pack_template_id)
VALUES (_club_id, _starter_pack_template_id);
```

Preservar toda validação, normalização, badge, crédito, assinatura e grants.

- [ ] **Step 6: Atualizar `open_initial_pack`**

Na função vigente, após validar dono/liga e bloquear pacote, retornar pacote aberto antes de checar elenco:

```sql
IF _pack.opened_at IS NOT NULL THEN
  RETURN QUERY
  SELECT _pack.id, _club_id, _pack.opened_at, ipi.player_id, ipi.slot
  FROM public.initial_pack_items ipi
  WHERE ipi.pack_id = _pack.id
  ORDER BY ipi.slot;
  RETURN;
END IF;
```

Validar template/elenco, bloquear cartas e exigir 10 disponíveis:

```sql
SELECT count(*)::integer INTO _current_roster
FROM public.club_players cp WHERE cp.club_id = _club.id;
IF _current_roster <> 0 THEN RAISE EXCEPTION 'initial_pack_requires_empty_roster'; END IF;
IF _pack.starter_pack_template_id IS NULL THEN RAISE EXCEPTION 'starter_pack_template_missing'; END IF;

SELECT count(*)::integer INTO _template_card_count
FROM public.starter_pack_template_items i
WHERE i.template_id = _pack.starter_pack_template_id;
IF _template_card_count <> 10 THEN RAISE EXCEPTION 'starter_pack_template_invalid'; END IF;

PERFORM cp.id
FROM public.starter_pack_template_items i
JOIN public.club_players cp ON cp.player_id = i.player_id
JOIN public.system_market_stock sms ON sms.club_player_id = cp.id
WHERE i.template_id = _pack.starter_pack_template_id
ORDER BY cp.id
FOR UPDATE OF cp, sms;

SELECT count(*)::integer INTO _available_card_count
FROM public.starter_pack_template_items i
JOIN public.club_players cp ON cp.player_id = i.player_id
JOIN public.system_market_stock sms ON sms.club_player_id = cp.id
WHERE i.template_id = _pack.starter_pack_template_id
  AND cp.club_id IS NULL
  AND NOT cp.is_reserved
  AND NOT sms.is_market_eligible;
IF _available_card_count <> 10 THEN RAISE EXCEPTION 'starter_pack_card_unavailable'; END IF;
```

Consumir somente template:

```sql
DELETE FROM public.system_market_stock sms
USING public.club_players cp, public.starter_pack_template_items i
WHERE sms.club_player_id = cp.id
  AND cp.player_id = i.player_id
  AND i.template_id = _pack.starter_pack_template_id
  AND NOT sms.is_market_eligible;

UPDATE public.club_players cp
SET club_id = _club_id, acquired_at = pg_catalog.now(), is_reserved = false
FROM public.starter_pack_template_items i
WHERE cp.player_id = i.player_id
  AND i.template_id = _pack.starter_pack_template_id
  AND cp.club_id IS NULL;

INSERT INTO public.initial_pack_items(pack_id, player_id, slot)
SELECT _pack.id, i.player_id, i.slot
FROM public.starter_pack_template_items i
WHERE i.template_id = _pack.starter_pack_template_id
ORDER BY i.slot;
```

Marcar `opened_at` e retornar `initial_pack_items` na ordem de slot, preservando assinatura/grants atuais.

- [ ] **Step 7: Aplicar e validar**

Run: migration, depois `fair_starter_packs.sql`.

Expected: NOTICE de sucesso.

- [ ] **Step 8: Commit**

```bash
git add supabase/migrations/20260713160000_fair_starter_packs.sql supabase/tests/database/fair_starter_packs.sql
git commit -m "feat: adicionar pacotes iniciais balanceados"
```

---

### Task 3: Adaptar testes SQL existentes

**Files:**
- Modify: `supabase/tests/database/open_initial_pack_concurrency.sql`
- Modify: `supabase/tests/database/closed_market_economy.sql`
- Modify: `supabase/tests/database/fair_starter_packs.sql`

**Interfaces:**
- Produces: testes independentes do estado real.

- [ ] **Step 1: Criar templates fixture**

Para cada pacote manual, criar código `PACKT01`, `PACKT02`, etc., com 10 jogadores fixture únicos:

```sql
INSERT INTO public.starter_pack_templates(id, code, expected_total_overall, expected_starter_overall)
VALUES (_template_id, 'PACKT01', 500, 250);

INSERT INTO public.starter_pack_template_items(template_id, player_id, slot)
SELECT _template_id, p.id, row_number() OVER (ORDER BY p.code)::smallint
FROM public.players p
WHERE p.code BETWEEN 'BFTST-001' AND 'BFTST-010';

INSERT INTO public.initial_packs(club_id, starter_pack_template_id)
VALUES (_club_id, _template_id);
```

- [ ] **Step 2: Atualizar todo insert de `initial_packs`**

Nenhum teste pode usar `INSERT INTO initial_packs(club_id)` sem template.

- [ ] **Step 3: Provar idempotência**

```sql
SELECT array_agg(player_id ORDER BY slot) INTO _first_open
FROM public.open_initial_pack(_club_id);
SELECT array_agg(player_id ORDER BY slot) INTO _second_open
FROM public.open_initial_pack(_club_id);
IF _first_open <> _second_open THEN
  RAISE EXCEPTION 'assertion_failed: reopened pack changed';
END IF;
IF (SELECT count(*) FROM public.initial_pack_items WHERE pack_id = _pack_id) <> 10 THEN
  RAISE EXCEPTION 'assertion_failed: reopened pack duplicated items';
END IF;
```

- [ ] **Step 4: Provar atomicidade**

Marcar uma carta do template como comercial, esperar `starter_pack_card_unavailable`, confirmar zero posse e zero itens.

```sql
UPDATE public.system_market_stock SET is_market_eligible = true
WHERE club_player_id = _fixture_card_id;

BEGIN
  PERFORM * FROM public.open_initial_pack(_club_id);
  RAISE EXCEPTION 'assertion_failed: unavailable pack opened';
EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
  IF _message <> 'starter_pack_card_unavailable' THEN RAISE; END IF;
END;

IF EXISTS (SELECT 1 FROM public.club_players WHERE club_id = _club_id)
   OR EXISTS (SELECT 1 FROM public.initial_pack_items WHERE pack_id = _pack_id) THEN
  RAISE EXCEPTION 'assertion_failed: partial opening';
END IF;
```

- [ ] **Step 5: Provar atribuição e exaustão**

Dentro da transação, reservar templates `PACK01..PACK06` livres com clubes fixture inseridos diretamente. Adicionar dois templates livres `PACKT11` e `PACKT12`, cada um com 10 novos jogadores fixture. Executar `create_club` para dois usuários aprovados e confirmar templates distintos. Terceira chamada deve retornar `starter_pack_templates_exhausted`.

```sql
IF (
  SELECT count(DISTINCT starter_pack_template_id)
  FROM public.initial_packs
  WHERE club_id = ANY(_created_club_ids)
) <> 2 THEN
  RAISE EXCEPTION 'assertion_failed: create_club repeated template';
END IF;
```

- [ ] **Step 6: Executar regressões**

Run:

```text
fair_starter_packs.sql
open_initial_pack_concurrency.sql
closed_market_economy.sql
```

Expected: NOTICE de sucesso; tudo termina em `ROLLBACK`.

- [ ] **Step 7: Commit**

```bash
git add supabase/tests/database/fair_starter_packs.sql supabase/tests/database/open_initial_pack_concurrency.sql supabase/tests/database/closed_market_economy.sql
git commit -m "test: cobrir abertura deterministica de pacotes"
```

---

### Task 4: Corrigir mercado `60/10`

**Files:**
- Create: `src/test/market-functions.test.ts`
- Modify: `src/lib/market.functions.ts`

**Interfaces:**
- Produces: `loadRoster(supabase, clubId)` exportada.
- Produces: `loadSystemMarket(supabase)` exportada.

- [ ] **Step 1: Escrever teste vermelho**

```ts
import { describe, expect, it, vi } from "vitest";
import { loadRoster, loadSystemMarket } from "@/lib/market.functions";

function queryMock(rows: unknown[] = []) {
  const order = vi.fn().mockResolvedValue({ data: rows, error: null });
  const eq = vi.fn(() => ({ order }));
  const select = vi.fn(() => ({ eq }));
  const from = vi.fn(() => ({ select }));
  return { client: { from } as never, from, eq };
}

describe("market functional scoping", () => {
  it("filters roster by club", async () => {
    const mock = queryMock();
    const clubId = "00000000-0000-0000-0000-000000000123";
    await loadRoster(mock.client, clubId);
    expect(mock.from).toHaveBeenCalledWith("club_players");
    expect(mock.eq).toHaveBeenCalledWith("club_id", clubId);
  });

  it("filters system stock by eligibility", async () => {
    const mock = queryMock();
    await loadSystemMarket(mock.client);
    expect(mock.from).toHaveBeenCalledWith("system_market_stock");
    expect(mock.eq).toHaveBeenCalledWith("is_market_eligible", true);
  });
});
```

- [ ] **Step 2: Confirmar falha**

```bash
bun run test -- src/test/market-functions.test.ts
```

Expected: exports/assinatura ausentes.

- [ ] **Step 3: Implementar filtros**

Em `loadRoster`, exportar, receber `clubId` e inserir antes de `.order(...)`:

```ts
.eq("club_id", clubId)
```

Em `loadSystemMarket`, exportar e inserir:

```ts
.eq("is_market_eligible", true)
```

Também incluir `code` na seleção aninhada de `players` do estoque, pois `playerSchema` exige `code`.

Resolver clube antes de carregar elenco:

```ts
async function loadOwnedClub(supabase: SupabaseClient<Database>, userId: string) {
  const result = await supabase
    .from("clubs")
    .select("id, name, abbreviation, balance_cents")
    .eq("owner_id", userId)
    .maybeSingle();
  if (result.error) throw new Error(mapMarketErrorMessage(result.error));
  return result.data;
}

export const getMyRoster = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const club = await loadOwnedClub(context.supabase, context.userId);
    return club ? loadRoster(context.supabase, club.id) : [];
  });

export const getMarketWorkspace = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const club = await loadOwnedClub(context.supabase, context.userId);
    if (!club) return { club: null, roster: [], systemMarket: [] };
    const [roster, systemMarket] = await Promise.all([
      loadRoster(context.supabase, club.id),
      loadSystemMarket(context.supabase),
    ]);
    return { club, roster, systemMarket };
  });
```

- [ ] **Step 4: Testar**

```bash
bun run test -- src/test/market-functions.test.ts src/test/market.test.ts
bun run typecheck
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/lib/market.functions.ts src/test/market-functions.test.ts
git commit -m "fix: limitar elenco e vitrine ao escopo correto"
```

---

### Task 5: Atualizar tipos Supabase

**Files:**
- Modify: `src/integrations/supabase/types.ts`

- [ ] **Step 1: Regenerar**

```bash
bunx supabase gen types typescript --project-id "$VITE_SUPABASE_PROJECT_ID" --schema public > src/integrations/supabase/types.ts
```

- [ ] **Step 2: Confirmar tipos**

Confirmar tabelas novas, relationships e:

```ts
initial_packs: {
  Row: {
    starter_pack_template_id: string;
  };
};
```

- [ ] **Step 3: Validar e commit**

```bash
bun run typecheck
bun run test -- src/test/market-functions.test.ts src/test/market.test.ts src/test/pack-opening.test.ts
git add src/integrations/supabase/types.ts
git commit -m "chore: atualizar tipos dos pacotes iniciais"
```

---

### Task 6: Documentar e verificar

**Files:**
- Modify: `README.md`
- Modify: `docs/RULES.md`
- Modify: `docs/PLAYER_CARDS.md`
- Modify: `docs/MARKET.md`
- Modify: `docs/SETUP_LOCAL.md`

- [ ] **Step 1: Atualizar regras**

Adicionar em `docs/RULES.md`:

```md
## Pacotes iniciais

- Existem 6 templates fechados e balanceados, com 10 cartas cada.
- Cada template contém 2 GK, 3 DEF, 3 MID e 2 ATA.
- Cada clube recebe aleatoriamente 1 template livre.
- Um template nunca é atribuído a dois clubes.
- A abertura transfere exatamente as 10 cartas persistidas no template.
- Reabrir a RPC retorna mesmos itens sem duplicação.
```

- [ ] **Step 2: Atualizar pacote e mercado**

Em `docs/PLAYER_CARDS.md`, registrar que `create_club` reserva template e `open_initial_pack` não sorteia cartas.

Em `docs/MARKET.md`, registrar filtros explícitos por `club_id` e `is_market_eligible = true`.

- [ ] **Step 3: Atualizar setup e README**

Adicionar `fair_starter_packs.sql` à lista de testes SQL.

Trocar README para:

```md
- **RPC `open_initial_pack`**: valida dono, status aprovado e liga em setup; transfere atomicamente as 10 cartas do template exclusivo reservado ao clube. Não existe sorteio carta a carta.
```

Atualizar contagem de tabelas de `24` para `26`.

- [ ] **Step 4: Check completo**

```bash
bun run format
bun run check
```

Expected: package manager, Prettier, ESLint, TypeScript, Vitest, PWA, assets e build passam.

- [ ] **Step 5: Validar UI/DB**

```text
Antes: /mercado -> Meu elenco 0/10
Depois: /mercado -> Meu elenco 10/10
Sistema: somente cartas vendidas por clubes
```

```sql
SELECT t.code, c.name
FROM public.initial_packs ip
JOIN public.starter_pack_templates t ON t.id = ip.starter_pack_template_id
JOIN public.clubs c ON c.id = ip.club_id
ORDER BY t.code;
```

Expected: sem template repetido; com 6 clubes, `PACK01..PACK06` completos.

- [ ] **Step 6: Commit**

```bash
git add README.md docs/RULES.md docs/PLAYER_CARDS.md docs/MARKET.md docs/SETUP_LOCAL.md
git commit -m "docs: registrar pacotes iniciais balanceados"
```

---

## Final Verification

- [ ] `git status --short` vazio.
- [ ] `bun run check` passa.
- [ ] 3 testes SQL passam.
- [ ] 6 templates de produção, 60 itens únicos.
- [ ] OVR: `579, 578, 579, 579, 578, 579`.
- [ ] Admin vê `0/10` antes e `10/10` depois.
- [ ] Pool inicial não aparece na vitrine.
- [ ] Migrations antigas intactas.
