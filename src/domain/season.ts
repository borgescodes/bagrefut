export const REQUIRED_SEASON_CLUBS = 6;
export const DEFAULT_SEASON_TIMEZONE = "America/Belem";

export type SeasonOperationalStatus =
  | "waiting_for_clubs"
  | "ready_to_start"
  | "active"
  | "finished";

export type RegistrationStatus = "open" | "closed";

export interface SeasonReadiness {
  status: Extract<SeasonOperationalStatus, "waiting_for_clubs" | "ready_to_start">;
  eligibleCount: number;
  requiredCount: number;
  missingCount: number;
}

export interface SeasonAdminConfigInput {
  name: string;
  startDate: string;
  defaultMatchTime: string;
  roundIntervalDays: number;
  timezone: string;
  registrationStatus: RegistrationStatus;
  registrationDeadline: string | null;
  prizesCents: readonly number[];
}

export interface SeasonAdminConfigValue {
  name: string;
  startDate: string;
  defaultMatchTime: string;
  roundIntervalDays: number;
  timezone: typeof DEFAULT_SEASON_TIMEZONE;
  registrationStatus: RegistrationStatus;
  registrationDeadline: string | null;
  prizesCents: number[];
}

export type ValidationResult<T> = { ok: true; value: T } | { ok: false; errors: string[] };

export interface SeasonRpcState {
  operational_status: SeasonOperationalStatus;
  eligible_count: number;
  required_count: number;
  missing_count: number;
  active_season: unknown;
  current_round: unknown;
  next_round: unknown;
  previous_round: unknown;
}

export interface SeasonUiState {
  operationalStatus: SeasonOperationalStatus;
  eligibleCount: number;
  requiredCount: number;
  missingCount: number;
  waitingMessage: string;
  canStartSeason: boolean;
}

export interface StandingsRpcRow {
  position: number;
  club_name: string;
  played: number;
  points: number;
  wins: number;
  draws: number;
  losses: number;
  goals_for: number;
  goals_against: number;
  goal_difference: number;
}

export interface FormattedStandingsRow {
  position: string;
  club: string;
  played: string;
  points: string;
  wins: string;
  draws: string;
  losses: string;
  goalsFor: string;
  goalsAgainst: string;
  goalDifference: string;
}

export interface SeasonAdminActionInput {
  operationalStatus: SeasonOperationalStatus;
  selectedClubCount: number;
  configValid: boolean;
  mutationPending: boolean;
}

export interface SeasonAdminActionState {
  disabled: boolean;
  reason: string | null;
}

export type SeasonClubSelectionResult =
  | { ok: true; selectedClubIds: string[] }
  | { ok: false; errors: string[] };

const DATE_ONLY_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const MATCH_TIME_PATTERN = /^\d{2}:\d{2}$/;

export function calculateSeasonReadiness(eligibleCount: number): SeasonReadiness {
  const safeEligibleCount = Math.max(0, Math.trunc(eligibleCount));
  const missingCount = Math.max(0, REQUIRED_SEASON_CLUBS - safeEligibleCount);
  return {
    status: missingCount > 0 ? "waiting_for_clubs" : "ready_to_start",
    eligibleCount: safeEligibleCount,
    requiredCount: REQUIRED_SEASON_CLUBS,
    missingCount,
  };
}

export function validateSeasonAdminConfig(
  input: SeasonAdminConfigInput,
): ValidationResult<SeasonAdminConfigValue> {
  const errors: string[] = [];
  const name = input.name.trim();

  if (name.length < 3 || name.length > 80) errors.push("season_name_invalid");
  if (!DATE_ONLY_PATTERN.test(input.startDate)) errors.push("season_start_date_invalid");
  if (!isValidMatchTime(input.defaultMatchTime)) errors.push("season_match_time_invalid");
  if (!Number.isInteger(input.roundIntervalDays) || input.roundIntervalDays < 1) {
    errors.push("season_round_interval_invalid");
  }
  if (input.timezone !== DEFAULT_SEASON_TIMEZONE) errors.push("season_timezone_invalid");
  if (
    input.prizesCents.length !== REQUIRED_SEASON_CLUBS ||
    input.prizesCents.some((amount) => !Number.isInteger(amount) || amount < 0)
  ) {
    errors.push("season_prizes_invalid");
  }

  if (errors.length > 0) return { ok: false, errors };

  return {
    ok: true,
    value: {
      name,
      startDate: input.startDate,
      defaultMatchTime: input.defaultMatchTime,
      roundIntervalDays: input.roundIntervalDays,
      timezone: DEFAULT_SEASON_TIMEZONE,
      registrationStatus: input.registrationStatus,
      registrationDeadline: input.registrationDeadline,
      prizesCents: [...input.prizesCents],
    },
  };
}

export function validateSeasonClubSelection(
  selectedClubIds: readonly string[],
  eligibleClubIds: readonly string[],
): SeasonClubSelectionResult {
  const selected = [...selectedClubIds];
  const errors: string[] = [];
  const unique = new Set(selected);
  const eligible = new Set(eligibleClubIds);

  if (unique.size !== selected.length) errors.push("season_selection_has_duplicates");
  if (selected.some((clubId) => !eligible.has(clubId))) {
    errors.push("season_selection_has_ineligible_club");
  }
  if (selected.length !== REQUIRED_SEASON_CLUBS) {
    errors.push("season_selection_requires_exactly_6");
  }

  if (errors.length > 0) return { ok: false, errors };
  return { ok: true, selectedClubIds: selected };
}

export function adaptSeasonRpcState(input: SeasonRpcState): SeasonUiState {
  const eligibleCount = Number(input.eligible_count);
  const requiredCount = Number(input.required_count);
  const missingCount = Number(input.missing_count);
  return {
    operationalStatus: input.operational_status,
    eligibleCount,
    requiredCount,
    missingCount,
    waitingMessage:
      missingCount > 0
        ? `${eligibleCount} de ${requiredCount} clubes confirmados. Faltam ${missingCount}.`
        : `${eligibleCount} de ${requiredCount} clubes confirmados.`,
    canStartSeason: input.operational_status === "ready_to_start",
  };
}

export function formatStandingsRow(row: StandingsRpcRow): FormattedStandingsRow {
  return {
    position: String(row.position),
    club: row.club_name,
    played: String(row.played),
    points: String(row.points),
    wins: String(row.wins),
    draws: String(row.draws),
    losses: String(row.losses),
    goalsFor: String(row.goals_for),
    goalsAgainst: String(row.goals_against),
    goalDifference:
      row.goal_difference > 0 ? `+${row.goal_difference}` : String(row.goal_difference),
  };
}

export function getSeasonAdminActionState(input: SeasonAdminActionInput): SeasonAdminActionState {
  if (input.mutationPending) return { disabled: true, reason: "Processando." };
  if (input.operationalStatus === "waiting_for_clubs") {
    return { disabled: true, reason: "Aguardando 6 clubes elegiveis." };
  }
  if (input.selectedClubCount !== REQUIRED_SEASON_CLUBS) {
    return { disabled: true, reason: "Selecione exatamente 6 clubes." };
  }
  if (!input.configValid) return { disabled: true, reason: "Revise a configuracao." };
  if (input.operationalStatus === "active") {
    return { disabled: true, reason: "Ja existe temporada ativa." };
  }
  return { disabled: false, reason: null };
}

function isValidMatchTime(value: string): boolean {
  if (!MATCH_TIME_PATTERN.test(value)) return false;
  const [hoursText, minutesText] = value.split(":");
  const hours = Number(hoursText);
  const minutes = Number(minutesText);
  return hours >= 0 && hours <= 23 && minutes >= 0 && minutes <= 59;
}
