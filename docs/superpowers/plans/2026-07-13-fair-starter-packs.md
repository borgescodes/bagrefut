# Fair Starter Packs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Trocar o sorteio solto por 6 pacotes iniciais fechados e exclusivos, corrigindo também o escopo do elenco e da vitrine para contas admin.

**Architecture:** Uma migration forward-only cria templates persistidos, semeia as 60 cartas, associa 1 template exclusivo a cada `initial_packs` e substitui `create_club`/`open_initial_pack`. Server functions do mercado passam a filtrar funcionalmente por `club_id` e `is_market_eligible`, sem depender da amplitude da RLS admin.

**Tech Stack:** PostgreSQL/Supabase, PL/pgSQL, RLS, TanStack Start, TypeScript 5.8, Supabase JS, Zod, Vitest 4, Bun.

## Global Constraints

- Criar exatamente 6 templates `PACK01` a `PACK06`.
- Cada template possui exatamente 10 jogadores: 2 GK, 3 DEF, 3 MID e 2 ATA.
- Cada jogador aparece em exatamente 1 template.
- Cada template pode pertencer a no máximo 1 clube.
- Atribuição do template é aleatória entre templates livres.
- Abertura entrega somente as cartas do template atribuído.
- Estoque comercial `is_market_eligible = true` nunca entra em pacote.
- Reabertura é idempotente e retorna os mesmos itens.
- Migration é forward-only. Não editar migrations já aplicadas.
- Conta admin deve ver somente cartas do próprio clube em `Meu elenco`.
- Conta admin deve ver somente estoque comercial em `Sistema`.
- Bun é gerenciador canônico. Usar `bun run`, nunca `bun test`.
- Não alterar OVR, atributos, preços, treino, formação ou simulador.

---

## File Map

- Create: `supabase/migrations/20260713160000_fair_starter_packs.sql` - schema, seed, backfill e RPCs.
- Create: `supabase/tests/database/fair_starter_packs.sql` - contrato dos 6 pacotes e abertura.
- Modify: `supabase/tests/database/open_initial_pack_concurrency.sql` - fixtures compatíveis com templates.
- Modify: `supabase/tests/database/closed_market_economy.sql` - pacote de teste com template próprio.
- Modify: `src/lib/market.functions.ts` - filtros explícitos e resolução sequencial do clube.
- Create: `src/test/market-functions.test.ts` - prova dos filtros no query builder.
- Modify: `src/integrations/supabase/types.ts` - tipos das novas tabelas e FK em `initial_packs`.
- Modify: `docs/RULES.md` - regra dos pacotes fechados.
- Modify: `docs/PLAYER_CARDS.md` - fluxo de atribuição/abertura.
- Modify: `docs/MARKET.md` - escopo funcional explícito.
- Modify: `docs/SETUP_LOCAL.md` - registrar novo teste SQL.
- Modify: `README.md` - remover descrição de sorteio de 10 cartas soltas.

---

### Task 1: Escrever contrato SQL dos templates

**Files:**
- Create: `supabase/tests/database/fair_starter_packs.sql`

**Interfaces:**
- Consumes: tabelas futuras `starter_pack_templates`, `starter_pack_template_items`; coluna futura `initial_packs.starter_pack_template_id`.
- Produces: teste transacional com NOTICE final `fair_starter_packs contract test passed`.

- [ ] **Step 1: Criar teste que falha antes da migration**

Começar arquivo com transação e definição canônica:

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
  _count integer;
BEGIN
  SELECT count(*) INTO _count FROM public.starter_pack_templates;
  IF _count <> 6 THEN
    RAISE EXCEPTION 'assertion_failed: expected 6 templates, got %', _count;
  END IF;

  SELECT count(*) INTO _count FROM public.starter_pack_template_items;
  IF _count <> 60 THEN
    RAISE EXCEPTION 'assertion_failed: expected 60 template items, got %', _count;
  END IF;

  SELECT count(DISTINCT player_id) INTO _count
  FROM public.starter_pack_template_items;
  IF _count <> 60 THEN
    RAISE EXCEPTION 'assertion_failed: player repeated between templates';
  END IF;

  FOR _code IN SELECT jsonb_object_keys(_expected) LOOP
    SELECT jsonb_agg(p.code ORDER BY i.slot)
    INTO _actual
    FROM public.starter_pack_templates t
    JOIN public.starter_pack_template_items i ON i.template_id = t.id
    JOIN public.players p ON p.id = i.player_id
    WHERE t.code = _code;

    IF _actual <> _expected -> _code THEN
      RAISE EXCEPTION 'assertion_failed: composition mismatch for %, got %', _code, _actual;
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM public.starter_pack_templates t
    JOIN public.starter_pack_template_items i ON i.template_id = t.id
    JOIN public.players p ON p.id = i.player_id
    GROUP BY t.id
    HAVING count(*) <> 10
       OR count(*) FILTER (WHERE p.position = 'GK') <> 2
       OR count(*) FILTER (WHERE p.position = 'DEF') <> 3
       OR count(*) FILTER (WHERE p.position = 'MID') <> 3
       OR count(*) FILTER (WHERE p.position = 'ATA') <> 2
       OR sum(p.overall) <> t.expected_total_overall
  ) THEN
    RAISE EXCEPTION 'assertion_failed: shape or OVR mismatch';
  END IF;

  IF EXISTS (
    SELECT starter_pack_template_id
    FROM public.initial_packs
    GROUP BY starter_pack_template_id
    HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'assertion_failed: template assigned twice';
  END IF;

  RAISE NOTICE 'fair_starter_packs contract test passed';
END;
$$;

ROLLBACK;
```

- [ ] **Step 2: Executar antes da migration**

Run: colar `supabase/tests/database/fair_starter_packs.sql` no SQL Editor.

Expected: FAIL com `relation "public.starter_pack_templates" does not exist`.

- [ ] **Step 3: Commit do teste vermelho**

```bash
git add supabase/tests/database/fair_starter_packs.sql
git commit -m "test: definir contrato dos pacotes iniciais"
```

---

### Task 2: Criar schema, seed, backfill e RPCs

**Files:**
- Create: `supabase/migrations/20260713160000_fair_starter_packs.sql`

**Interfaces:**
- Produces: `starter_pack_templates`, `starter_pack_template_items`, `initial_packs.starter_pack_template_id`.
- Produces: `create_club(text,text,text) returns uuid` preservado.
- Produces: `open_initial_pack(uuid)` com colunas `pack_id, club_id, opened_at, player_id, slot` preservadas.

- [ ] **Step 1: Adicionar preflight antes de qualquer DDL**

Usar uma CTE de definições única para validar 60 códigos, estado resetado e somas:

```sql
DO $$
DECLARE
  _expected_codes text[] := ARRAY[
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
  IF cardinality(_expected_codes) <> 60
     OR (SELECT count(DISTINCT x) FROM unnest(_expected_codes) AS x) <> 60 THEN
    RAISE EXCEPTION 'fair_starter_packs_invalid_definition';
  END IF;
  IF (SELECT count(*) FROM public.players WHERE code = ANY(_expected_codes)) <> 60 THEN
    RAISE EXCEPTION 'fair_starter_packs_player_code_missing';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM public.players p
    JOIN public.club_players cp ON cp.player_id = p.id
    LEFT JOIN public.system_market_stock sms ON sms.club_player_id = cp.id
    WHERE p.code = ANY(_expected_codes)
      AND (cp.club_id IS NOT NULL OR cp.is_reserved OR sms.club_player_id IS NULL OR sms.is_market_eligible)
  ) THEN
    RAISE EXCEPTION 'fair_starter_packs_card_not_in_initial_pool';
  END IF;
END;
$$;
```

- [ ] **Step 2: Criar tabelas e coluna nullable**

```sql
CREATE TABLE public.starter_pack_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE CHECK (code ~ '^PACK0[1-6]$'),
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
  ADD CONSTRAINT initial_packs_starter_template_unique
  UNIQUE (starter_pack_template_id);
```

- [ ] **Step 3: Semear templates e itens pela ordem informada**

```sql
WITH definitions(code, expected_total_overall, expected_starter_overall, player_codes) AS (
  VALUES
    ('PACK01', 579::smallint, 335::smallint, ARRAY['GK05','GK11','DEF11','DEF09','DEF03','MID04','MID14','MID13','ATA01','ATA12']::text[]),
    ('PACK02', 578::smallint, 335::smallint, ARRAY['GK01','GK03','DEF05','DEF02','DEF16','MID08','MID09','MID18','ATA07','ATA08']::text[]),
    ('PACK03', 579::smallint, 336::smallint, ARRAY['GK02','GK12','DEF10','DEF14','DEF13','MID05','MID06','MID15','ATA04','ATA03']::text[]),
    ('PACK04', 579::smallint, 336::smallint, ARRAY['GK06','GK09','DEF07','DEF08','DEF18','MID07','MID02','MID12','ATA06','ATA09']::text[]),
    ('PACK05', 578::smallint, 336::smallint, ARRAY['GK07','GK10','DEF01','DEF17','DEF12','MID10','MID03','MID17','ATA02','ATA11']::text[]),
    ('PACK06', 579::smallint, 336::smallint, ARRAY['GK04','GK08','DEF04','DEF06','DEF15','MID01','MID11','MID16','ATA05','ATA10']::text[])
), inserted AS (
  INSERT INTO public.starter_pack_templates(code, expected_total_overall, expected_starter_overall)
  SELECT code, expected_total_overall, expected_starter_overall
  FROM definitions
  RETURNING id, code
)
INSERT INTO public.starter_pack_template_items(template_id, player_id, slot)
SELECT i.id, p.id, u.slot::smallint
FROM definitions d
JOIN inserted i USING (code)
CROSS JOIN LATERAL unnest(d.player_codes) WITH ORDINALITY AS u(player_code, slot)
JOIN public.players p ON p.code = u.player_code;
```

Adicionar validação pós-seed:

```sql
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.starter_pack_templates t
    JOIN public.starter_pack_template_items i ON i.template_id = t.id
    JOIN public.players p ON p.id = i.player_id
    GROUP BY t.id
    HAVING count(*) <> 10 OR sum(p.overall) <> t.expected_total_overall
  ) THEN
    RAISE EXCEPTION 'fair_starter_packs_seed_validation_failed';
  END IF;
END;
$$;
```

- [ ] **Step 4: Backfill aleatório e tornar coluna obrigatória**

```sql
WITH packs AS (
  SELECT ip.id, row_number() OVER (ORDER BY pg_catalog.random(), ip.id) AS rn
  FROM public.initial_packs ip
), templates AS (
  SELECT t.id, row_number() OVER (ORDER BY pg_catalog.random(), t.id) AS rn
  FROM public.starter_pack_templates t
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

ALTER TABLE public.initial_packs
  ALTER COLUMN starter_pack_template_id SET NOT NULL;
```

- [ ] **Step 5: Substituir `create_club` preservando validações atuais**

Na definição mais recente, adicionar variável:

```sql
_starter_pack_template_id uuid;
```

Antes do `INSERT INTO public.clubs`, reservar template:

```sql
SELECT t.id
INTO _starter_pack_template_id
FROM public.starter_pack_templates t
WHERE NOT EXISTS (
  SELECT 1
  FROM public.initial_packs ip
  WHERE ip.starter_pack_template_id = t.id
)
ORDER BY pg_catalog.random(), t.id
LIMIT 1
FOR UPDATE SKIP LOCKED;

IF _starter_pack_template_id IS NULL THEN
  RAISE EXCEPTION 'starter_pack_templates_exhausted';
END IF;
```

Trocar criação do pacote por:

```sql
INSERT INTO public.initial_packs(club_id, starter_pack_template_id)
VALUES (_club_id, _starter_pack_template_id);
```

Manter assinatura, grants, nome normalizado, sigla, badge, saldo inicial e erros existentes exatamente como na migration `20260707214653_fix_club_identity_and_badges.sql`.

- [ ] **Step 6: Substituir `open_initial_pack` por leitura determinística**

Preservar assinatura atual. Mover idempotência antes da validação de elenco:

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

Validar template e disponibilidade:

```sql
IF _pack.starter_pack_template_id IS NULL THEN
  RAISE EXCEPTION 'starter_pack_template_missing';
END IF;

SELECT count(*)::integer
INTO _template_card_count
FROM public.starter_pack_template_items i
WHERE i.template_id = _pack.starter_pack_template_id;

IF _template_card_count <> 10 THEN
  RAISE EXCEPTION 'starter_pack_template_invalid';
END IF;

PERFORM cp.id
FROM public.starter_pack_template_items i
JOIN public.club_players cp ON cp.player_id = i.player_id
JOIN public.system_market_stock sms ON sms.club_player_id = cp.id
WHERE i.template_id = _pack.starter_pack_template_id
ORDER BY cp.id
FOR UPDATE OF cp, sms;

SELECT count(*)::integer
INTO _available_card_count
FROM public.starter_pack_template_items i
JOIN public.club_players cp ON cp.player_id = i.player_id
JOIN public.system_market_stock sms ON sms.club_player_id = cp.id
WHERE i.template_id = _pack.starter_pack_template_id
  AND cp.club_id IS NULL
  AND NOT cp.is_reserved
  AND NOT sms.is_market_eligible;

IF _available_card_count <> 10 THEN
  RAISE EXCEPTION 'starter_pack_card_unavailable';
END IF;
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
SET club_id = _club_id,
    acquired_at = pg_catalog.now(),
    is_reserved = false
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

Marcar `opened_at`, validar `ROW_COUNT` quando aplicável e retornar `initial_pack_items` na ordem de slot. Manter grants atuais.

- [ ] **Step 7: Aplicar migration e rodar teste dedicado**

Run: aplicar `supabase/migrations/20260713160000_fair_starter_packs.sql` no SQL Editor.

Run: executar `supabase/tests/database/fair_starter_packs.sql`.

Expected: NOTICE `fair_starter_packs contract test passed`.

- [ ] **Step 8: Commit**

```bash
git add supabase/migrations/20260713160000_fair_starter_packs.sql supabase/tests/database/fair_starter_packs.sql
git commit -m "feat: adicionar pacotes iniciais balanceados"
```

---

### Task 3: Adaptar regressões SQL e provar idempotência/atomicidade

**Files:**
- Modify: `supabase/tests/database/open_initial_pack_concurrency.sql`
- Modify: `supabase/tests/database/closed_market_economy.sql`
- Modify: `supabase/tests/database/fair_starter_packs.sql`

**Interfaces:**
- Consumes: RPC determinística `open_initial_pack`.
- Produces: fixtures independentes dos 6 templates reais.

- [ ] **Step 1: Criar template temporário por pacote fixture**

Nos testes que inserem jogadores `BFTST-*` ou `BFCM-*`, após criar 10 jogadores do pacote, criar template transacional:

```sql
INSERT INTO public.starter_pack_templates(
  id, code, expected_total_overall, expected_starter_overall
)
VALUES (
  _test_template_id,
  'TEST01',
  500,
  250
);

INSERT INTO public.starter_pack_template_items(template_id, player_id, slot)
SELECT _test_template_id, p.id, row_number() OVER (ORDER BY p.code)::smallint
FROM public.players p
WHERE p.code BETWEEN 'BFTST-001' AND 'BFTST-010';

INSERT INTO public.initial_packs(club_id, starter_pack_template_id)
VALUES (_test_club_id, _test_template_id);
```

Como constraint de produção aceita somente `PACK01` a `PACK06`, não usar `TEST01` no schema final. Para fixtures, gerar códigos válidos adicionais não é possível. Portanto, substituir check do campo por formato genérico `^[A-Z0-9_]{4,16}$`, enquanto seed de produção e teste dedicado garantem exatamente `PACK01..PACK06`. Usar códigos de fixture `TSTC01`, `TSTC02`, etc.

- [ ] **Step 2: Atualizar todos `INSERT INTO initial_packs`**

Cada inserção manual deve informar `starter_pack_template_id`. Nenhum teste pode depender de template livre do ambiente.

- [ ] **Step 3: Provar reabertura idempotente**

Após primeira abertura:

```sql
SELECT array_agg(player_id ORDER BY slot)
INTO _first_open
FROM public.open_initial_pack(_club_id);

SELECT array_agg(player_id ORDER BY slot)
INTO _second_open
FROM public.open_initial_pack(_club_id);

IF _first_open <> _second_open THEN
  RAISE EXCEPTION 'assertion_failed: reopened pack changed cards';
END IF;
```

Confirmar `count(*) = 10` em `initial_pack_items` e ausência de duplicação.

- [ ] **Step 4: Provar falha atômica**

Antes de abrir pacote fixture, transformar uma carta em comercial:

```sql
UPDATE public.system_market_stock
SET is_market_eligible = true
WHERE club_player_id = _fixture_card_id;
```

Esperar `starter_pack_card_unavailable`, depois confirmar:

```sql
IF EXISTS (SELECT 1 FROM public.club_players WHERE club_id = _club_id) THEN
  RAISE EXCEPTION 'assertion_failed: partial ownership after failed opening';
END IF;

IF EXISTS (SELECT 1 FROM public.initial_pack_items WHERE pack_id = _pack_id) THEN
  RAISE EXCEPTION 'assertion_failed: partial pack items after failed opening';
END IF;
```

- [ ] **Step 5: Provar estoque comercial não consumido**

No teste de economia fechada, manter carta comercial e afirmar que ela continua na vitrine após abertura de pacote de outro template.

- [ ] **Step 6: Executar testes SQL**

Run, nesta ordem, no SQL Editor:

```text
supabase/tests/database/fair_starter_packs.sql
supabase/tests/database/open_initial_pack_concurrency.sql
supabase/tests/database/closed_market_economy.sql
```

Expected: NOTICE de sucesso em cada arquivo; todos terminam em `ROLLBACK`.

- [ ] **Step 7: Commit**

```bash
git add supabase/tests/database/fair_starter_packs.sql supabase/tests/database/open_initial_pack_concurrency.sql supabase/tests/database/closed_market_economy.sql
git commit -m "test: cobrir abertura deterministica de pacotes"
```

---

### Task 4: Corrigir escopo funcional do mercado

**Files:**
- Create: `src/test/market-functions.test.ts`
- Modify: `src/lib/market.functions.ts:235-257,430-517`

**Interfaces:**
- Produces: `loadRoster(supabase, clubId)` exportada para teste.
- Produces: `loadSystemMarket(supabase)` exportada para teste.

- [ ] **Step 1: Escrever teste vermelho do query builder**

```ts
import { describe, expect, it, vi } from "vitest";
import { loadRoster, loadSystemMarket } from "@/lib/market.functions";

function queryMock(rows: unknown[] = []) {
  const order = vi.fn().mockResolvedValue({ data: rows, error: null });
  const eq = vi.fn(() => ({ order }));
  const select = vi.fn(() => ({ eq }));
  const from = vi.fn(() => ({ select }));
  return { client: { from } as never, from, select, eq, order };
}

describe("market functional scoping", () => {
  it("filters roster by the authenticated club id", async () => {
    const mock = queryMock();
    await loadRoster(mock.client, "00000000-0000-0000-0000-000000000123");
    expect(mock.from).toHaveBeenCalledWith("club_players");
    expect(mock.eq).toHaveBeenCalledWith("club_id", "00000000-0000-0000-0000-000000000123");
  });

  it("filters system market to commercial stock", async () => {
    const mock = queryMock();
    await loadSystemMarket(mock.client);
    expect(mock.from).toHaveBeenCalledWith("system_market_stock");
    expect(mock.eq).toHaveBeenCalledWith("is_market_eligible", true);
  });
});
```

- [ ] **Step 2: Executar teste vermelho**

Run:

```bash
bun run test -- src/test/market-functions.test.ts
```

Expected: FAIL porque helpers não são exportadas e não recebem `clubId`.

- [ ] **Step 3: Implementar filtros mínimos**

Alterar helpers:

```ts
export async function loadRoster(
  supabase: SupabaseClient<Database>,
  clubId: string,
): Promise<RosterMarketCard[]> {
  const { data, error } = await supabase
    .from("club_players")
    .select(/* seleção existente */)
    .eq("club_id", clubId)
    .order("acquired_at", { ascending: true });
  // parsing existente
}

export async function loadSystemMarket(
  supabase: SupabaseClient<Database>,
): Promise<SystemMarketCard[]> {
  const { data, error } = await supabase
    .from("system_market_stock")
    .select(/* seleção existente */)
    .eq("is_market_eligible", true)
    .order("acquired_at", { ascending: true });
  // parsing existente
}
```

Trocar server functions:

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

`listSystemMarketStock` continua chamando `loadSystemMarket(context.supabase)`.

- [ ] **Step 4: Executar testes focados**

```bash
bun run test -- src/test/market-functions.test.ts src/test/market.test.ts
```

Expected: PASS.

- [ ] **Step 5: Typecheck**

```bash
bun run typecheck
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/lib/market.functions.ts src/test/market-functions.test.ts
git commit -m "fix: limitar elenco e vitrine ao escopo correto"
```

---

### Task 5: Regenerar tipos Supabase

**Files:**
- Modify: `src/integrations/supabase/types.ts`

**Interfaces:**
- Produces: tipos para `starter_pack_templates`, `starter_pack_template_items` e FK de `initial_packs`.

- [ ] **Step 1: Gerar tipos após migration aplicada**

```bash
bunx supabase gen types typescript --project-id "$VITE_SUPABASE_PROJECT_ID" --schema public > src/integrations/supabase/types.ts
```

- [ ] **Step 2: Validar diff obrigatório**

Confirmar presença de:

```ts
starter_pack_templates: {
  Row: {
    code: string;
    created_at: string;
    expected_starter_overall: number;
    expected_total_overall: number;
    id: string;
  };
  // Insert e Update equivalentes
};

starter_pack_template_items: {
  Row: {
    player_id: string;
    slot: number;
    template_id: string;
  };
  // Insert, Update e Relationships
};
```

Confirmar em `initial_packs.Row/Insert/Update`:

```ts
starter_pack_template_id: string;
```

- [ ] **Step 3: Executar typecheck e testes**

```bash
bun run typecheck
bun run test -- src/test/market-functions.test.ts src/test/market.test.ts src/test/pack-opening.test.ts
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add src/integrations/supabase/types.ts
git commit -m "chore: atualizar tipos dos pacotes iniciais"
```

---

### Task 6: Atualizar documentação e validação final

**Files:**
- Modify: `README.md`
- Modify: `docs/RULES.md`
- Modify: `docs/PLAYER_CARDS.md`
- Modify: `docs/MARKET.md`
- Modify: `docs/SETUP_LOCAL.md`

**Interfaces:**
- Produces: documentação consistente com implementação.

- [ ] **Step 1: Atualizar regras**

Em `docs/RULES.md`, inserir seção antes de `Carta permanente e estoque do sistema`:

```md
## Pacotes iniciais

- Existem 6 templates fechados e balanceados, com 10 cartas cada.
- Cada template contém 2 GK, 3 DEF, 3 MID e 2 ATA.
- Cada clube recebe aleatoriamente 1 template ainda livre.
- Um template nunca é atribuído a dois clubes.
- A abertura transfere exatamente as 10 cartas persistidas no template.
- Reabrir a RPC retorna os mesmos itens sem duplicar posse ou registros.
```

- [ ] **Step 2: Atualizar documentação do pacote**

Em `docs/PLAYER_CARDS.md`, trocar texto que diga sorteio por:

```md
- `create_club` reserva aleatoriamente um dos 6 templates livres.
- `open_initial_pack` não sorteia cartas: consome exatamente o template associado ao pacote.
- Slots persistidos no template são copiados para `initial_pack_items`.
- Ordem visual de revelação continua sendo responsabilidade do frontend e não muda a composição.
```

- [ ] **Step 3: Atualizar mercado**

Em `docs/MARKET.md`, substituir “consulta somente cartas acessíveis por RLS” por:

```md
`Meu elenco` filtra explicitamente `club_players.club_id` pelo clube do usuário. RLS continua como defesa, mas não define o escopo funcional da tela. `Sistema` filtra explicitamente `system_market_stock.is_market_eligible = true`, inclusive para admin.
```

- [ ] **Step 4: Atualizar setup e README**

Adicionar `fair_starter_packs.sql` à lista de testes SQL em `docs/SETUP_LOCAL.md`.

No README, substituir descrição da RPC:

```md
- **RPC `open_initial_pack`**: valida dono, status aprovado e liga em setup; transfere atomicamente as 10 cartas do template exclusivo reservado ao clube. Não existe sorteio carta a carta.
```

Atualizar contagem de tabelas de `24` para `26` onde aplicável.

- [ ] **Step 5: Formatar e executar check completo**

```bash
bun run format
bun run check
```

Expected: todos estágios PASS: package manager, Prettier, ESLint, TypeScript, Vitest, PWA, assets e build.

- [ ] **Step 6: Revisão manual mínima**

Com conta admin e pacote fechado:

```text
/mercado -> Meu elenco: 0/10
/mercado -> Sistema: somente cartas vendidas por clubes
```

Após abrir:

```text
/abrir-pacote -> exatamente 10 cartas do template atribuído
/mercado -> Meu elenco: 10/10
```

Criar 6 clubes em ambiente limpo e consultar:

```sql
SELECT t.code, c.name
FROM public.initial_packs ip
JOIN public.starter_pack_templates t ON t.id = ip.starter_pack_template_id
JOIN public.clubs c ON c.id = ip.club_id
ORDER BY t.code;
```

Expected: 6 linhas, `PACK01` a `PACK06`, nenhum código repetido.

- [ ] **Step 7: Commit final**

```bash
git add README.md docs/RULES.md docs/PLAYER_CARDS.md docs/MARKET.md docs/SETUP_LOCAL.md
git commit -m "docs: registrar pacotes iniciais balanceados"
```

---

## Final Verification

- [ ] `git status --short` mostra árvore limpa.
- [ ] `bun run check` passa.
- [ ] `fair_starter_packs.sql` passa.
- [ ] `open_initial_pack_concurrency.sql` passa.
- [ ] `closed_market_economy.sql` passa.
- [ ] 6 templates, 60 itens, 60 jogadores únicos.
- [ ] OVR total por pacote: `579, 578, 579, 579, 578, 579`.
- [ ] Admin vê `0/10` antes e `10/10` depois.
- [ ] Estoque inicial nunca aparece na vitrine.
- [ ] Nenhuma migration antiga foi alterada.
