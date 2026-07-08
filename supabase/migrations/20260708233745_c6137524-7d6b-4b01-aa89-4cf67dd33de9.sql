
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM anon;

GRANT EXECUTE ON FUNCTION public.create_club(text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_club_identity(uuid, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.open_initial_pack(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.buy_player_from_system(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sell_player_to_system(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.train_club_player(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_lineup(uuid, public.formation, public.play_style, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_user_status(uuid, public.user_status, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_match_score_summaries(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_approved_user(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.user_participates_in_match(uuid, uuid) TO authenticated;
