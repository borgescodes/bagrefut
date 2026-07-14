-- Nomes oficiais de display para os 18 meio-campistas.
-- Fonte autoritativa: players-organizado-reduzido.xlsx (somente trim aplicado).
-- Forward-only e idempotente; nenhuma coluna além de players.name é alterada.

DO $$
DECLARE
  _expected integer := 18;
  _missing text;
  _invalid text;
  _updated integer;
  _inconsistent text;
BEGIN
  CREATE TEMP TABLE _mid_player_display_names (
    code text PRIMARY KEY,
    display_name text NOT NULL
  ) ON COMMIT DROP;

  INSERT INTO _mid_player_display_names (code, display_name) VALUES
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

  IF (SELECT count(*) FROM _mid_player_display_names) <> _expected THEN
    RAISE EXCEPTION 'mid_player_display_names: mapeamento deve ter % códigos, encontrou %',
      _expected, (SELECT count(*) FROM _mid_player_display_names);
  END IF;

  SELECT string_agg(code, ', ' ORDER BY code)
  INTO _invalid
  FROM _mid_player_display_names
  WHERE code !~ '^MID(0[1-9]|1[0-8])$'
     OR display_name IS DISTINCT FROM btrim(display_name);

  IF _invalid IS NOT NULL THEN
    RAISE EXCEPTION 'mid_player_display_names: códigos ou nomes inválidos: %', _invalid;
  END IF;

  SELECT string_agg(m.code, ', ' ORDER BY m.code)
  INTO _missing
  FROM _mid_player_display_names m
  LEFT JOIN public.players p ON p.code = m.code
  WHERE p.id IS NULL;

  IF _missing IS NOT NULL THEN
    RAISE EXCEPTION 'mid_player_display_names: códigos ausentes em public.players: %', _missing;
  END IF;

  UPDATE public.players p
  SET name = btrim(m.display_name)
  FROM _mid_player_display_names m
  WHERE p.code = m.code
    AND p.name IS DISTINCT FROM btrim(m.display_name);

  GET DIAGNOSTICS _updated = ROW_COUNT;

  SELECT string_agg(m.code, ', ' ORDER BY m.code)
  INTO _inconsistent
  FROM _mid_player_display_names m
  JOIN public.players p ON p.code = m.code
  WHERE p.name IS DISTINCT FROM btrim(m.display_name)
     OR p.name IS DISTINCT FROM btrim(p.name);

  IF _inconsistent IS NOT NULL THEN
    RAISE EXCEPTION 'mid_player_display_names: estado final inconsistente para: %', _inconsistent;
  END IF;

  RAISE NOTICE 'mid_player_display_names: % linhas atualizadas; 18 códigos consistentes.', _updated;
END;
$$;
