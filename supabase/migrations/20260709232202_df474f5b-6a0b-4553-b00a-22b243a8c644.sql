
UPDATE auth.users u
SET email_confirmed_at = now()
FROM public.profiles p
WHERE p.id = u.id AND p.status = 'approved' AND u.email_confirmed_at IS NULL;

CREATE OR REPLACE FUNCTION public.admin_set_user_status(_target_user_id uuid, _new_status public.user_status, _reason text DEFAULT NULL::text)
 RETURNS TABLE(target_user_id uuid, previous_status public.user_status, new_status public.user_status, audit_log_id uuid, changed_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  _actor_id uuid := auth.uid();
  _actor_profile public.profiles%ROWTYPE;
  _target_profile public.profiles%ROWTYPE;
  _previous_status public.user_status;
  _audit_log_id uuid;
  _changed_at timestamptz := pg_catalog.now();
BEGIN
  IF _actor_id IS NULL THEN RAISE EXCEPTION 'unauthenticated'; END IF;
  IF _target_user_id IS NULL THEN RAISE EXCEPTION 'target_profile_not_found'; END IF;
  IF _new_status IS NULL THEN RAISE EXCEPTION 'invalid_status'; END IF;

  SELECT * INTO _actor_profile FROM public.profiles WHERE id = _actor_id;
  IF _actor_profile.id IS NULL THEN RAISE EXCEPTION 'profile_not_found'; END IF;
  IF _actor_profile.status <> 'approved' THEN RAISE EXCEPTION 'profile_not_approved'; END IF;
  IF NOT public.has_role(_actor_id, 'admin'::public.app_role) THEN RAISE EXCEPTION 'forbidden_not_admin'; END IF;

  SELECT * INTO _target_profile FROM public.profiles WHERE id = _target_user_id FOR UPDATE;
  IF _target_profile.id IS NULL THEN RAISE EXCEPTION 'target_profile_not_found'; END IF;

  _previous_status := _target_profile.status;

  UPDATE public.profiles
  SET status = _new_status, updated_at = _changed_at
  WHERE id = _target_user_id;

  IF _new_status = 'approved'::public.user_status THEN
    UPDATE auth.users
    SET email_confirmed_at = COALESCE(email_confirmed_at, _changed_at)
    WHERE id = _target_user_id;
  END IF;

  INSERT INTO public.admin_audit_logs (admin_id, action, target_table, target_id, payload, created_at)
  VALUES (_actor_id, 'admin_set_user_status', 'profiles', _target_user_id,
    pg_catalog.jsonb_build_object(
      'actor_user_id', _actor_id,
      'target_user_id', _target_user_id,
      'previous_status', _previous_status,
      'new_status', _new_status,
      'reason', _reason,
      'changed_at', _changed_at
    ), _changed_at)
  RETURNING id INTO _audit_log_id;

  RETURN QUERY SELECT _target_user_id, _previous_status, _new_status, _audit_log_id, _changed_at;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_set_user_status(uuid, public.user_status, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_set_user_status(uuid, public.user_status, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_set_user_status(uuid, public.user_status, text) TO authenticated;
