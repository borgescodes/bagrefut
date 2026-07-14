# Fair Starter Packs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Trocar sorteio de 10 cartas soltas por 6 pacotes iniciais fechados, exclusivos e balanceados, além de corrigir escopo do elenco e vitrine para admin.

**Architecture:** Migration forward-only cria templates persistidos, semeia as 60 cartas, associa um template exclusivo a cada `initial_packs` e substitui `create_club`/`open_initial_pack`. Mercado passa a filtrar funcionalmente por `club_id` e `is_market_eligible`, mantendo RLS como defesa.

**Tech Stack:** PostgreSQL/Supabase, PL/pgSQL, RLS, TanStack Start, TypeScript 5.8, Supabase JS, Zod, Vitest 4, Bun.

## Global Constraints

- Produção contém exatamente `PACK01` a `PACK06`.
- Cada pacote contém 10 jogadores: 2 GK, 3 DEF, 3 MID, 2 ATA.
- Cada jogador aparece em um único pacote.
- Cada template pertence a no máximo um clube.
- Atribuição é aleatória entre templates livres.
- Abertura entrega somente cartas do template atribuído.
- Carta comercial `is_market_eligible = true` nunca entra em pacote.
- Reabertura retorna mesmos itens sem nova mutação.
- Migration é forward-only. Não editar migrations aplicadas.
- Admin vê somente próprio elenco e estoque comercial.
- Bun é gerenciador canônico. Usar `bun run`, nunca `bun test`.
- Não alterar OVR, atributos, preços, treino, formação ou simulador.

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

### Task 1: Escrever contrato SQL vermelho

**Files:**
- Create: `supabase/tests/database/fair_starter_packs.sql`

**Interfaces:**
- Consumes: `starter_pack_templates`, `starter_pack_template_items`, `initial_packs.starter_pack_template_id`.
- Produces: NOTICE `fair_starter_packs contract test passed`.

- [ ] **Step 1: Criar teste estrutural**

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
  SELECT count(*) INTO _count FROM public.starter_pack_templates WHERE code LIKE 'PACK%';
  IF _count <> 6 THEN
    RAISE EXCEPTION 'assertion_failed: expected 6 production templates, got %', _count;
  END IF;

  SELECT count(*) INTO _count
  FROM public.starter_pack_template_items i
  JOIN public.starter_pack_templates t ON t.id = i.template_id
  WHERE t.code LIKE 'PACK%';
  IF _count <> 60 THEN
    RAISE EXCEPTION 'assertion_failed: expected 60 production template items, got %', _count;
  END IF;

  SELECT count(DISTINCT i.player_id) INTO _count
  FROM public.starter_pack_template_items i
  JOIN public.starter_pack_templates t ON t.id = i.template_id
  WHERE t.code LIKE 'PACK%';
  IF _count <> 60 THEN
    RAISE EXCEPTION 'assertion_failed: player repeated between production templates';
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
    WHERE t.code LIKE 'PACK%'
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

Run: SQL Editor com `supabase/tests/database/fair_starter_packs.sql`.

Expected: FAIL com `relation "public.starter_pack_templates" does not exist`.

- [ ] **Step 3: Commit**

```bash
git add supabase/tests/database/fair_starter_packs.sql
git commit -m "test: definir contrato dos pacotes iniciais"
```

---

### Task 2: Criar migration de templates e RPCs

**Files:**
- Create: `supabase/migrations/20260713160000_fair_starter_packs.sql`

**Interfaces:**
- Produces: tabelas `starter_pack_templates`, `starter_pack_template_items`.
- Produces: `initial_packs.starter_pack_template_id uuid not null unique`.
- Preserva: `create_club(text,text,text) returns uuid`.
- Preserva: `open_initial_pack(uuid)` retornando `pack_id, club_id, opened_at, player_id, slot`.

- [ ] **Step 1: Adicionar preflight completo antes do DDL**

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
  IF (
    SELECT count(*)
    FROM public.players p
    JOIN public.club_players cp ON cp.player_id = p.id
    JOIN public.system_market_stock sms ON sms.club_player_id = cp.id
    WHERE p.code = ANY(_expected_codes)
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

- [ ] **Step 2: Criar schema privado e coluna nullable**

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

- [ ] **Step 3: Semear produção na ordem informada**

```sql
WITH definitions(code, expected_total_overall, expected_starter_overall, player_codes) AS (
  VALUES
    ('PACK01',579::smallint,335::smallint,ARRAY['GK05','GK11','DEF11','DEF09','DEF03','MID04','MID14','MID13','ATA01','ATA12']::text[]),
    ('PACK02',578::smallint,335::smallint,ARRAY['GK01','GK03','DEF05','DEF02','DEF16','MID08','MID09','MID18','ATA07','ATA08']::text[]),
    ('PACK03',579::smallint,336::smallint,ARRAY['GK02','GK12','DEF10','DEF14','DEF13','MID05','MID06','MID15','ATA04','ATA03']::text[]),
    ('PACK04',579::smallint,336::smallint,ARRAY['GK06','GK09','DEF07','DEF08','DEF18','MID07','MID02','MID12','ATA06','ATA09']::text[]),
    ('PACK05',578::smallint,336::smallint,ARRAY['GK07','GK10','DEF01','DEF17','DEF12','MID10','MID03','MID17','ATA02','ATA11']::text[]),
    ('PACK06',579::smallint,336::smallint,ARRAY['GK04','GK08','DEF04','DEF06','DEF15','MID01','MID11','MID16','ATA05','ATA10']::text[])
), inserted AS (
  INSERT INTO public.starter_pack_templates(code, expected_total_overall, expected_starter_overall)
  SELECT code, expected_total_overall, expected_starter_overall FROM definitions
  RETURNING id, code
)
INSERT INTO public.starter_pack_template_items(template_id, player_id, slot)
SELECT t.id, p.id, u.slot::smallint
FROM definitions d
JOIN inserted t USING (code)
CROSS JOIN LATERAL unnest(d.player_codes) WITH ORDINALITY AS u(player_code, slot)
JOIN public.players p ON p.code = u.player_code;
```

- [ ] **Step 4: Backfill aleatório e aplicar NOT NULL**

```sql
WITH packs AS (
  SELECT id, row_number() OVER (ORDER BY pg_catalog.random(), id) AS rn
  FROM public.initial_packs
), templates AS (
  SELECT id, row_number() OVER (ORDER BY pg_catalog.random(), id) AS rn
  FROM public.starter_pack_templates
  WHERE code LIKE 'PACK%'
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

- [ ] **Step 5: Substituir `create_club` preservando validações atuais**

Copiar integralmente função mais recente de `20260707214653_fix_club_identity_and_badges.sql`. Adicionar variável:

```sql
_starter_pack_template_id uuid;
```

Antes de inserir clube:

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

Trocar somente criação do pacote:

```sql
INSERT INTO public.initial_packs(club_id, starter_pack_template_id)
VALUES (_club_id, _starter_pack_template_id);
```

Manter assinatura, grants, normalização, validações, badge e crédito inicial sem outras mudanças.

- [ ] **Step 6: Substituir `open_initial_pack`**

Adicionar variáveis:

```sql
_template_card_count integer;
_available_card_count integer;
_current_roster integer;
_opened_at timestamptz;
```

Após bloquear e validar pacote, retornar idempotentemente antes de checar elenco:

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

Validar elenco vazio e template:

```sql
SELECT count(*)::integer INTO _current_roster
FROM public.club_players cp WHERE cp.club_id = _club.id;
IF _current_roster <> 0 THEN
  RAISE EXCEPTION 'initial_pack_requires_empty_roster';
END IF;
IF _pack.starter_pack_template_id IS NULL THEN
  RAISE EXCEPTION 'starter_pack_template_missing';
END IF;
SELECT count(*)::integer INTO _template_card_count
FROM public.starter_pack_template_items i
WHERE i.template_id = _pack.starter_pack_template_id;
IF _template_card_count <> 10 THEN
  RAISE EXCEPTION 'starter_pack_template_invalid';
END IF;
```

Bloquear e validar cartas:

```sql
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
IF _available_card_count <> 10 THEN
  RAISE EXCEPTION 'starter_pack_card_unavailable';
END IF;
```

Consumir template:

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

UPDATE public.initial_packs ip
SET opened_at = pg_catalog.now()
WHERE ip.id = _pack.id AND ip.opened_at IS NULL
RETURNING ip.opened_at INTO _opened_at;

IF _opened_at IS NULL THEN
  RAISE EXCEPTION 'pack_already_opened';
END IF;

RETURN QUERY
SELECT _pack.id, _club_id, _opened_at, ipi.player_id, ipi.slot
FROM public.initial_pack_items ipi
WHERE ipi.pack_id = _pack.id
ORDER BY ipi.slot;
```

Manter auth, profile, dono, liga, assinatura e grants da função atual.

- [ ] **Step 7: Aplicar migration e executar contrato**

Run: migration no SQL Editor, depois `fair_starter_packs.sql`.

Expected: NOTICE `fair_starter_packs contract test passed`.

- [ ] **Step 8: Commit**

```bash
git add supabase/migrations/20260713160000_fair_starter_packs.sql supabase/tests/database/fair_starter_packs.sql
git commit -m "feat: adicionar pacotes iniciais balanceados"
```

---

### Task 3: Adaptar regressões SQL

**Files:**
- Modify: `supabase/tests/database/open_initial_pack_concurrency.sql`
- Modify: `supabase/tests/database/closed_market_economy.sql`
- Modify: `supabase/tests/database/fair_starter_packs.sql`

**Interfaces:**
- Consumes: template obrigatório e abertura idempotente.
- Produces: fixtures transacionais independentes do estado real.

- [ ] **Step 1: Criar templates temporários para fixtures**

Para cada pacote fixture, declarar UUID fixo, criar template `TSTC01`, `TSTC02`, etc., e mapear 10 jogadores próprios:

```sql
INSERT INTO public.starter_pack_templates(
  id, code, expected_total_overall, expected_starter_overall
)
VALUES (_test_template_id, 'TSTC01', 500, 250);

INSERT INTO public.starter_pack_template_items(template_id, player_id, slot)
SELECT _test_template_id, p.id, row_number() OVER (ORDER BY p.code)::smallint
FROM public.players p
WHERE p.code BETWEEN 'BFTST-001' AND 'BFTST-010';

INSERT INTO public.initial_packs(club_id, starter_pack_template_id)
VALUES (_test_club_id, _test_template_id);
```

Repetir com códigos/UUIDs distintos para clubes que precisam de pacote. Não reutilizar jogador entre templates devido `UNIQUE(player_id)`.

- [ ] **Step 2: Atualizar todos inserts manuais em `initial_packs`**

Todo `INSERT INTO public.initial_packs(club_id)` vira `INSERT INTO public.initial_packs(club_id, starter_pack_template_id)` com template fixture próprio.

- [ ] **Step 3: Provar idempotência**

```sql
SELECT array_agg(player_id ORDER BY slot) INTO _first_open
FROM public.open_initial_pack(_club_id);
SELECT array_agg(player_id ORDER BY slot) INTO _second_open
FROM public.open_initial_pack(_club_id);
IF _first_open <> _second_open THEN
  RAISE EXCEPTION 'assertion_failed: reopened pack changed cards';
END IF;
IF (SELECT count(*) FROM public.initial_pack_items WHERE pack_id = _pack_id) <> 10 THEN
  RAISE EXCEPTION 'assertion_failed: reopened pack duplicated items';
END IF;
```

- [ ] **Step 4: Provar atomicidade e estoque comercial**

Marcar uma carta do template como comercial, esperar `starter_pack_card_unavailable` e confirmar zero posse/itens:

```sql
UPDATE public.system_market_stock SET is_market_eligible = true
WHERE club_player_id = _fixture_card_id;

BEGIN
  PERFORM * FROM public.open_initial_pack(_club_id);
  RAISE EXCEPTION 'assertion_failed: unavailable template opened';
EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS _message = MESSAGE_TEXT;
  IF _message <> 'starter_pack_card_unavailable' THEN RAISE; END IF;
END;

IF EXISTS (SELECT 1 FROM public.club_players WHERE club_id = _club_id)
   OR EXISTS (SELECT 1 FROM public.initial_pack_items WHERE pack_id = _pack_id) THEN
  RAISE EXCEPTION 'assertion_failed: partial opening persisted';
END IF;
```

- [ ] **Step 5: Cobrir atribuição e exaustão**

No teste dedicado, reservar todos templates `PACK%` ainda livres com clubes fixture inseridos diretamente. Criar dois templates livres `TSTC11`/`TSTC12`, cada um com 10 novos jogadores fixture. Chamar `create_club` para dois usuários aprovados e confirmar IDs de template distintos. Terceira chamada deve falhar com `starter_pack_templates_exhausted`.

Consulta de asserção:

```sql
IF (
  SELECT count(DISTINCT ip.starter_pack_template_id)
  FROM public.initial_packs ip
  WHERE ip.club_id = ANY(_created_club_ids)
) <> 2 THEN
  RAISE EXCEPTION 'assertion_failed: create_club repeated template';
END IF;
```

- [ ] **Step 6: Executar testes SQL**

Run em ordem:

```text
fair_starter_packs.sql
open_initial_pack_concurrency.sql
closed_market_economy.sql
```

Expected: NOTICE de sucesso; cada arquivo termina em `ROLLBACK`.

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
  it("filters roster by club id", async () => {
    const mock = queryMock();
    const clubId = "00000000-0000-0000-0000-000000000123";
    await loadRoster(mock.client, clubId);
    expect(mock.from).toHaveBeenCalledWith("club_players");
    expect(mock.eq).toHaveBeenCalledWith("club_id", clubId);
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

```bash
bun run test -- src/test/market-functions.test.ts
```

Expected: FAIL por exports/assinatura ausentes.

- [ ] **Step 3: Implementar `loadRoster` completo**

```ts
export async function loadRoster(
  supabase: SupabaseClient<Database>,
  clubId: string,
): Promise<RosterMarketCard[]> {
  const { data, error } = await supabase
    .from("club_players")
    .select(`
      id,
      acquired_at,
      is_reserved,
      players (
        id, code, name, position, rarity, sector, overall,
        velocity, finishing, passing, dribbling, defending, physical, goalkeeping,
        reference_value_cents
      ),
      club_player_attribute_progress (attribute, progress, updated_at)
    `)
    .eq("club_id", clubId)
    .order("acquired_at", { ascending: true });
  if (error) throw new Error(mapMarketErrorMessage(error));
  return z.array(rosterRowSchema).parse(data ?? []).flatMap((row) => {
    if (!row.players) return [];
    return [{
      ...mapPlayer(row.id, row.players, systemBuyPriceCents(row.players.reference_value_cents)),
      acquiredAt: row.acquired_at,
      isReserved: row.is_reserved,
      systemSalePriceCents: systemBuyPriceCents(row.players.reference_value_cents),
      trainingCostCents: trainingCostCents(row.players.rarity),
      attributeProgress: (row.club_player_attribute_progress ?? []).map((progress) => ({
        attribute: progress.attribute,
        progress: progress.progress,
        updatedAt: progress.updated_at,
      })),
    }];
  });
}
```

- [ ] **Step 4: Implementar `loadSystemMarket` completo**

```ts
export async function loadSystemMarket(
  supabase: SupabaseClient<Database>,
): Promise<SystemMarketCard[]> {
  const { data, error } = await supabase
    .from("system_market_stock")
    .select(`
      club_player_id,
      acquired_at,
      club_players (
        id, club_id, is_reserved,
        players (
          id, code, name, position, rarity, sector, overall,
          velocity, finishing, passing, dribbling, defending, physical, goalkeeping,
          reference_value_cents
        )
      )
    `)
    .eq("is_market_eligible", true)
    .order("acquired_at", { ascending: true });
  if (error) throw new Error(mapMarketErrorMessage(error));
  return z.array(stockRowSchema).parse(data ?? []).flatMap((row) => {
    const card = row.club_players;
    if (!card?.players) return [];
    return [{
      ...mapPlayer(row.club_player_id, card.players, systemSellPriceCents(card.players.reference_value_cents)),
      acquiredAt: row.acquired_at,
      isAvailable: card.club_id === null && !card.is_reserved,
    }];
  });
}
```

Nota: seleção atual de `loadSystemMarket` omite `code`, mas `playerSchema` exige `code`. Incluir `code` corrige contrato Zod junto com filtro.

- [ ] **Step 5: Resolver clube antes do elenco**

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

- [ ] **Step 6: Executar testes e typecheck**

```bash
bun run test -- src/test/market-functions.test.ts src/test/market.test.ts
bun run typecheck
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add src/lib/market.functions.ts src/test/market-functions.test.ts
git commit -m "fix: limitar elenco e vitrine ao escopo correto"
```

---

### Task 5: Regenerar tipos Supabase

**Files:**
- Modify: `src/integrations/supabase/types.ts`

**Interfaces:**
- Produces: novas tabelas e FK tipadas.

- [ ] **Step 1: Gerar tipos após aplicar migration**

```bash
bunx supabase gen types typescript --project-id "$VITE_SUPABASE_PROJECT_ID" --schema public > src/integrations/supabase/types.ts
```

- [ ] **Step 2: Confirmar diff**

Confirmar tabelas `starter_pack_templates`, `starter_pack_template_items`, relationships para `players`/templates e campo obrigatório abaixo em `initial_packs.Row`:

```ts
starter_pack_template_id: string;
```

- [ ] **Step 3: Validar**

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

### Task 6: Atualizar documentação e validar tudo

**Files:**
- Modify: `README.md`
- Modify: `docs/RULES.md`
- Modify: `docs/PLAYER_CARDS.md`
- Modify: `docs/MARKET.md`
- Modify: `docs/SETUP_LOCAL.md`

**Interfaces:**
- Produces: documentação consistente.

- [ ] **Step 1: Documentar regras**

Adicionar em `docs/RULES.md`:

```md
## Pacotes iniciais

- Existem 6 templates fechados e balanceados, com 10 cartas cada.
- Cada template contém 2 GK, 3 DEF, 3 MID e 2 ATA.
- Cada clube recebe aleatoriamente 1 template ainda livre.
- Um template nunca é atribuído a dois clubes.
- A abertura transfere exatamente as 10 cartas persistidas no template.
- Reabrir a RPC retorna os mesmos itens sem duplicar posse ou registros.
```

- [ ] **Step 2: Documentar abertura**

Adicionar em `docs/PLAYER_CARDS.md`:

```md
- `create_club` reserva aleatoriamente um dos 6 templates livres.
- `open_initial_pack` não sorteia cartas: consome exatamente o template associado.
- Slots do template são copiados para `initial_pack_items`.
- Ordenação visual do frontend não altera composição nem posse.
```

- [ ] **Step 3: Documentar mercado**

Substituir seção de posse em `docs/MARKET.md` por:

```md
`Meu elenco` filtra explicitamente `club_players.club_id` pelo clube do usuário. RLS continua como defesa, mas não define o escopo funcional da tela. `Sistema` filtra explicitamente `system_market_stock.is_market_eligible = true`, inclusive para admin.
```

- [ ] **Step 4: Atualizar setup e README**

Adicionar `fair_starter_packs.sql` à lista de testes em `docs/SETUP_LOCAL.md`.

Trocar descrição da RPC no README por:

```md
- **RPC `open_initial_pack`**: valida dono, status aprovado e liga em setup; transfere atomicamente as 10 cartas do template exclusivo reservado ao clube. Não existe sorteio carta a carta.
```

Atualizar contagem de tabelas de `24` para `26` onde aparecer.

- [ ] **Step 5: Formatar e executar check completo**

```bash
bun run format
bun run check
```

Expected: package manager, Prettier, ESLint, TypeScript, Vitest, PWA, assets e build passam.

- [ ] **Step 6: Validar manualmente**

Antes de abrir:

```text
/mercado -> Meu elenco: 0/10
/mercado -> Sistema: somente cartas vendidas por clubes
```

Depois de abrir:

```text
/abrir-pacote -> 10 cartas do template atribuído
/mercado -> Meu elenco: 10/10
```

Auditoria DB:

```sql
SELECT t.code, c.name
FROM public.initial_packs ip
JOIN public.starter_pack_templates t ON t.id = ip.starter_pack_template_id
JOIN public.clubs c ON c.id = ip.club_id
ORDER BY t.code;
```

Expected: no máximo 6 linhas; nenhum `t.code` repetido. Com 6 clubes, `PACK01` a `PACK06` completos.

- [ ] **Step 7: Commit**

```bash
git add README.md docs/RULES.md docs/PLAYER_CARDS.md docs/MARKET.md docs/SETUP_LOCAL.md
git commit -m "docs: registrar pacotes iniciais balanceados"
```

---

## Final Verification

- [ ] `git status --short` vazio.
- [ ] `bun run check` passa.
- [ ] `fair_starter_packs.sql` passa.
- [ ] `open_initial_pack_concurrency.sql` passa.
- [ ] `closed_market_economy.sql` passa.
- [ ] Produção tem 6 templates e 60 itens únicos.
- [ ] OVR total: `579, 578, 579, 579, 578, 579`.
- [ ] Admin vê `0/10` antes e `10/10` depois.
- [ ] Pool inicial não aparece na vitrine.
- [ ] Nenhuma migration antiga foi alterada.
