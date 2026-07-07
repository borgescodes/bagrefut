-- Restrict direct table access for lineup persistence.
-- All authenticated writes must go through public.save_lineup(...).

BEGIN;

REVOKE ALL PRIVILEGES
ON TABLE public.lineups, public.lineup_players
FROM authenticated;

GRANT SELECT
ON TABLE public.lineups, public.lineup_players
TO authenticated;

COMMIT;
