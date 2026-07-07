
-- =====================================================================
-- BAGREFUT - Migration 005: seed 60 players
-- =====================================================================

WITH plan AS (
  -- (position, rarity, count) buckets
  SELECT * FROM (VALUES
    ('GK'::public.player_position,  'peba'::public.player_rarity, 7),
    ('GK',  'paia', 4),
    ('GK',  'pika', 1),
    ('DEF', 'peba',11),
    ('DEF', 'paia', 6),
    ('DEF', 'pika', 1),
    ('MID', 'peba',10),
    ('MID', 'paia', 6),
    ('MID', 'pika', 2),
    ('ATA', 'peba', 7),
    ('ATA', 'paia', 4),
    ('ATA', 'pika', 1)
  ) t(position, rarity, cnt)
),
expanded AS (
  SELECT
    p.position,
    p.rarity,
    generate_series(1, p.cnt) AS pos_index,
    row_number() OVER (PARTITION BY p.position ORDER BY p.rarity, generate_series(1, p.cnt)) AS position_seq
  FROM plan p
),
final AS (
  SELECT
    e.position,
    e.rarity,
    e.position_seq,
    CASE e.position WHEN 'GK' THEN 'GK' WHEN 'DEF' THEN 'DEF' WHEN 'MID' THEN 'MID' ELSE 'ATA' END
      || lpad(e.position_seq::text, 2, '0') AS code,
    -- deterministic OVR inside rarity band, using position_seq as offset
    CASE e.rarity
      WHEN 'peba' THEN 40 + ((e.position_seq * 7) % 20)      -- 40..59
      WHEN 'paia' THEN 60 + ((e.position_seq * 5) % 15)      -- 60..74
      WHEN 'pika' THEN 75 + ((e.position_seq * 3) % 15)      -- 75..89
    END AS ovr,
    (ARRAY[
      'centro','cidade_nova','promissao','jaderlandia','uraim','jardim',
      'flamboyant','angelim','camboata','buriti','laercio','bela_vista',
      'nagibao','ipixuna','caipe','paulo_sexto','morada_do_sol','morada_do_vento',
      'nova_conquista'
    ]::public.player_sector[])[1 + ((e.position_seq * 11) % 19)] AS sector,
    CASE e.rarity
      WHEN 'peba' THEN 50  + ((e.position_seq * 37) % 450)     -- R$0,50 - R$5,00
      WHEN 'paia' THEN 501 + ((e.position_seq * 97) % 1999)    -- R$5,01 - R$25,00
      WHEN 'pika' THEN 2501 + ((e.position_seq * 401) % 7499)  -- R$25,01 - R$100,00
    END AS ref_cents
  FROM expanded e
)
INSERT INTO public.players
  (code, name, position, rarity, sector, overall,
   velocity, finishing, passing, dribbling, defending, physical, goalkeeping,
   reference_value_cents)
SELECT
  f.code,
  f.code AS name,
  f.position,
  f.rarity,
  f.sector,
  f.ovr::smallint,
  f.ovr::smallint, f.ovr::smallint, f.ovr::smallint, f.ovr::smallint,
  f.ovr::smallint, f.ovr::smallint, f.ovr::smallint,
  f.ref_cents::integer
FROM final f
ON CONFLICT (code) DO NOTHING;
