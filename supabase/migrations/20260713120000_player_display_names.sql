-- Nomes oficiais de display para os 42 jogadores com foto (ATA/DEF/GK).
-- Fonte autoritativa: players-organizado-reduzido.xlsx (nomes já com trim aplicado).
-- players.name é o nome de display; players.code segue como identificador técnico.
-- Jogadores MID não são alterados aqui.
-- Forward-only e idempotente: reaplicar produz o mesmo estado final.
-- Nomes duplicados são intencionais (VOZINHA existe em ATA11 e GK09).

DO $$
DECLARE
  _expected integer := 42;
  _missing text;
  _updated integer;
BEGIN
  CREATE TEMP TABLE _player_display_names (
    code text PRIMARY KEY,
    display_name text NOT NULL
  ) ON COMMIT DROP;

  INSERT INTO _player_display_names (code, display_name) VALUES
    ('ATA01', 'PORCÃO DA TELE SENNA'),
    ('ATA02', 'ROBINHO'),
    ('ATA03', 'EPSTEIN'),
    ('ATA04', 'JANJA LULA DA SILVA'),
    ('ATA05', 'ZÉ FELIPE'),
    ('ATA06', 'DAVI BRITTO'),
    ('ATA07', 'GORDAO DA XJ6'),
    ('ATA08', 'MAJIN BOO'),
    ('ATA09', 'TUNG TUNG TUNG SAHUR'),
    ('ATA10', 'MARK ZUCKERBECK'),
    ('ATA11', 'VOZINHA'),
    ('ATA12', 'PATOLINO CAVA UMA FALTA'),
    ('DEF01', 'BOA MORTE'),
    ('DEF02', 'CASSETI'),
    ('DEF03', 'PAULÃO'),
    ('DEF04', 'ALIMAAMAR'),
    ('DEF05', 'SAKHO'),
    ('DEF06', 'MARQUINHOS'),
    ('DEF07', 'SEU MADRUGA'),
    ('DEF08', 'JOÃO PICA'),
    ('DEF09', 'BOCCHETTI'),
    ('DEF10', 'JOSÉ MUCIO'),
    ('DEF11', 'SHOTTA'),
    ('DEF12', 'DANILO FLAMENGO'),
    ('DEF13', 'PANTERA COR DE SHOTA'),
    ('DEF14', 'WELLINGTON'),
    ('DEF15', 'PABLINHA'),
    ('DEF16', 'EMERSON ROYAL'),
    ('DEF17', 'FELIX'),
    ('DEF18', 'PIKACHU'),
    ('GK01', 'MARTINEZZ'),
    ('GK02', 'NEUER'),
    ('GK03', 'MULHER DAS TEMARIS'),
    ('GK04', 'GOLEIRO DE PACACETE'),
    ('GK05', 'MAMONO ENDO'),
    ('GK06', 'TARAFEEL'),
    ('GK07', 'XEON SUZUKI'),
    ('GK08', 'HENRIQUE APOSENTADO'),
    ('GK09', 'VOZINHA'),
    ('GK10', 'VENON'),
    ('GK11', 'IGOR REZENDE'),
    ('GK12', 'CABEÇA DE ROLON');

  IF (SELECT count(*) FROM _player_display_names) <> _expected THEN
    RAISE EXCEPTION 'player_display_names: mapeamento deve ter % códigos, encontrou %',
      _expected, (SELECT count(*) FROM _player_display_names);
  END IF;

  SELECT string_agg(m.code, ', ' ORDER BY m.code)
  INTO _missing
  FROM _player_display_names m
  LEFT JOIN public.players p ON p.code = m.code
  WHERE p.id IS NULL;

  IF _missing IS NOT NULL THEN
    RAISE EXCEPTION 'player_display_names: códigos ausentes em public.players: %', _missing;
  END IF;

  -- updated_at é mantido pelo trigger trg_players_updated_at; o UPDATE só
  -- toca linhas cujo nome realmente muda, preservando idempotência.
  UPDATE public.players p
  SET name = btrim(m.display_name)
  FROM _player_display_names m
  WHERE p.code = m.code
    AND p.name IS DISTINCT FROM btrim(m.display_name);

  GET DIAGNOSTICS _updated = ROW_COUNT;

  IF NOT EXISTS (
    SELECT 1 FROM _player_display_names m
    JOIN public.players p ON p.code = m.code
    WHERE p.name IS DISTINCT FROM btrim(m.display_name)
  ) THEN
    RAISE NOTICE 'player_display_names: % linhas atualizadas; 42 códigos consistentes.', _updated;
  ELSE
    RAISE EXCEPTION 'player_display_names: estado final inconsistente após UPDATE.';
  END IF;
END;
$$;
