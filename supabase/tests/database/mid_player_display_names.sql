BEGIN;

DO $$
DECLARE
  _expected integer := 18;
  _actual integer;
  _updated integer;
  _mismatch text;
BEGIN
  CREATE TEMP TABLE _expected_mid_player_display_names (
    code text PRIMARY KEY,
    display_name text NOT NULL
  ) ON COMMIT DROP;

  INSERT INTO _expected_mid_player_display_names (code, display_name) VALUES
    ('MID01', 'Gauvao'),
    ('MID02', 'BELLIGOL'),
    ('MID03', 'BAD 2'),
    ('MID04', 'KIKO'),
    ('MID05', 'ALOKque'),
    ('MID06', 'sei la'),
    ('MID07', 'DOLI'),
    ('MID08', 'TCHOLA'),
    ('MID09', 'MANEL GOMES'),
    ('MID10', 'PAPAI KRISS'),
    ('MID11', 'BAD LINDO'),
    ('MID12', 'MIA KHALIFA'),
    ('MID13', 'GORDOMIRO'),
    ('MID14', 'AIII NOBRU'),
    ('MID15', 'RUSBÉ'),
    ('MID16', 'PESSE'),
    ('MID17', 'NEIMAR JUNIO'),
    ('MID18', 'GAYSTAVO');

  SELECT count(*) INTO _actual
  FROM public.players
  WHERE code ~ '^MID(0[1-9]|1[0-8])$';

  IF _actual <> _expected THEN
    RAISE EXCEPTION 'mid_player_display_names test: esperava 18 códigos MID, encontrou %', _actual;
  END IF;

  SELECT string_agg(e.code, ', ' ORDER BY e.code)
  INTO _mismatch
  FROM _expected_mid_player_display_names e
  JOIN public.players p ON p.code = e.code
  WHERE p.name IS DISTINCT FROM e.display_name
     OR p.name IS DISTINCT FROM btrim(p.name);

  IF _mismatch IS NOT NULL THEN
    RAISE EXCEPTION 'mid_player_display_names test: nomes divergentes ou com espaço externo: %', _mismatch;
  END IF;

  CREATE TEMP TABLE _non_mid_names_before ON COMMIT DROP AS
  SELECT code, name
  FROM public.players
  WHERE code ~ '^(ATA(0[1-9]|1[0-2])|DEF(0[1-9]|1[0-8])|GK(0[1-9]|1[0-2]))$';

  IF (SELECT count(*) FROM _non_mid_names_before) <> 42 THEN
    RAISE EXCEPTION 'mid_player_display_names test: esperava 42 códigos ATA/DEF/GK protegidos';
  END IF;

  UPDATE public.players p
  SET name = btrim(e.display_name)
  FROM _expected_mid_player_display_names e
  WHERE p.code = e.code
    AND p.name IS DISTINCT FROM btrim(e.display_name);

  GET DIAGNOSTICS _updated = ROW_COUNT;

  IF _updated <> 0 THEN
    RAISE EXCEPTION 'mid_player_display_names test: migration não é idempotente; % linhas mudaram', _updated;
  END IF;

  SELECT string_agg(b.code, ', ' ORDER BY b.code)
  INTO _mismatch
  FROM _non_mid_names_before b
  JOIN public.players p ON p.code = b.code
  WHERE p.name IS DISTINCT FROM b.name;

  IF _mismatch IS NOT NULL THEN
    RAISE EXCEPTION 'mid_player_display_names test: ATA/DEF/GK alterados durante o teste: %', _mismatch;
  END IF;

  RAISE NOTICE 'mid_player_display_names contract test passed';
END;
$$;

ROLLBACK;
