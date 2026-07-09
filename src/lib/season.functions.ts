import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import {
  DEFAULT_SEASON_TIMEZONE,
  validateSeasonAdminConfig,
  validateSeasonClubSelection,
} from "@/domain/season";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import type { Json } from "@/integrations/supabase/types";

const seasonSetupInput = z.object({
  name: z.string(),
  startDate: z.string(),
  defaultMatchTime: z.string(),
  roundIntervalDays: z.number(),
  timezone: z.string().default(DEFAULT_SEASON_TIMEZONE),
  registrationStatus: z.enum(["open", "closed"]),
  registrationDeadline: z.string().nullable(),
  prizesCents: z.array(z.number()),
});

const seasonParticipantsInput = z.object({
  configId: z.string().uuid(),
  selectedClubIds: z.array(z.string().uuid()),
  eligibleClubIds: z.array(z.string().uuid()),
});

const configIdInput = z.object({ configId: z.string().uuid() });
const optionalSeasonIdInput = z.object({ seasonId: z.string().uuid().optional() }).optional();

export const getSeasonOperationalState = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { data, error } = await context.supabase.rpc("get_season_operational_state");
    if (error) throw new Error(error.message);
    return data;
  });

export const getSeasonStandings = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .validator((data: unknown) => optionalSeasonIdInput.parse(data))
  .handler(async ({ data, context }) => {
    const { data: standings, error } = await context.supabase.rpc("get_season_standings", {
      _season_id: data?.seasonId,
    });
    if (error) throw new Error(error.message);
    return { standings: standings ?? [] };
  });

export const getSeasonHistory = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { data, error } = await context.supabase.rpc("get_season_history");
    if (error) throw new Error(error.message);
    return data;
  });

export const adminGetSeasonSetup = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { data, error } = await context.supabase.rpc("admin_get_season_setup");
    if (error) throw new Error(error.message);
    return data;
  });

export const adminSaveSeasonSetup = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((data: unknown) => seasonSetupInput.parse(data))
  .handler(async ({ data, context }) => {
    const validation = validateSeasonAdminConfig(data);
    if (!validation.ok) throw new Error(validation.errors[0] ?? "season_config_invalid");

    const config: Json = {
      name: validation.value.name,
      start_date: validation.value.startDate,
      default_match_time: validation.value.defaultMatchTime,
      round_interval_days: validation.value.roundIntervalDays,
      timezone: validation.value.timezone,
      registration_status: validation.value.registrationStatus,
      registration_deadline: validation.value.registrationDeadline,
      prizes_cents: validation.value.prizesCents,
    };

    const { data: result, error } = await context.supabase.rpc("admin_upsert_season_setup", {
      _config: config,
    });
    if (error) throw new Error(error.message);
    return result;
  });

export const adminSetSeasonParticipants = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((data: unknown) => seasonParticipantsInput.parse(data))
  .handler(async ({ data, context }) => {
    const validation = validateSeasonClubSelection(data.selectedClubIds, data.eligibleClubIds);
    if (!validation.ok) throw new Error(validation.errors[0] ?? "season_selection_invalid");

    const { data: result, error } = await context.supabase.rpc("admin_set_season_participants", {
      _config_id: data.configId,
      _club_ids: validation.selectedClubIds,
    });
    if (error) throw new Error(error.message);
    return result;
  });

export const adminStartSeason = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((data: unknown) => configIdInput.parse(data))
  .handler(async ({ data, context }) => {
    const { data: result, error } = await context.supabase.rpc("season_start", {
      _config_id: data.configId,
    });
    if (error) throw new Error(error.message);
    return result;
  });

export const adminFinishSeason = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((data: unknown) => optionalSeasonIdInput.parse(data))
  .handler(async ({ data, context }) => {
    const { data: result, error } = await context.supabase.rpc("season_finish", {
      _season_id: data?.seasonId,
    });
    if (error) throw new Error(error.message);
    return result;
  });
