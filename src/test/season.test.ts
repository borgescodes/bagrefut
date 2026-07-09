import { describe, expect, it } from "vitest";
import {
  DEFAULT_SEASON_TIMEZONE,
  REQUIRED_SEASON_CLUBS,
  adaptSeasonRpcState,
  calculateSeasonReadiness,
  formatStandingsRow,
  getSeasonAdminActionState,
  validateSeasonAdminConfig,
  validateSeasonClubSelection,
} from "@/domain/season";

describe("season domain helpers", () => {
  it("calculates waiting state and missing clubs", () => {
    expect(calculateSeasonReadiness(4)).toEqual({
      status: "waiting_for_clubs",
      eligibleCount: 4,
      requiredCount: REQUIRED_SEASON_CLUBS,
      missingCount: 2,
    });
  });

  it("marks exactly 6 clubs as ready to start", () => {
    expect(calculateSeasonReadiness(6)).toEqual({
      status: "ready_to_start",
      eligibleCount: 6,
      requiredCount: REQUIRED_SEASON_CLUBS,
      missingCount: 0,
    });
  });

  it("validates admin configuration without floating point money", () => {
    const result = validateSeasonAdminConfig({
      name: "Temporada 1",
      startDate: "2026-08-01",
      defaultMatchTime: "22:00",
      roundIntervalDays: 1,
      timezone: DEFAULT_SEASON_TIMEZONE,
      registrationStatus: "open",
      registrationDeadline: "2026-07-31",
      prizesCents: [600, 500, 400, 300, 200, 100],
    });

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.prizesCents).toEqual([600, 500, 400, 300, 200, 100]);
    }
  });

  it("rejects invalid admin configuration", () => {
    const result = validateSeasonAdminConfig({
      name: "T",
      startDate: "2026-08-01T12:00:00Z",
      defaultMatchTime: "9:00",
      roundIntervalDays: 0,
      timezone: "browser",
      registrationStatus: "closed",
      registrationDeadline: null,
      prizesCents: [100, 80, 60],
    });

    expect(result).toEqual({
      ok: false,
      errors: [
        "season_name_invalid",
        "season_start_date_invalid",
        "season_match_time_invalid",
        "season_round_interval_invalid",
        "season_timezone_invalid",
        "season_prizes_invalid",
      ],
    });
  });

  it("requires exactly 6 unique eligible clubs", () => {
    const eligibleClubIds = ["A", "B", "C", "D", "E", "F", "G"];

    expect(validateSeasonClubSelection(["A", "B", "C", "D", "E", "F"], eligibleClubIds)).toEqual({
      ok: true,
      selectedClubIds: ["A", "B", "C", "D", "E", "F"],
    });
    expect(validateSeasonClubSelection(["A", "B", "C", "D", "E"], eligibleClubIds)).toEqual({
      ok: false,
      errors: ["season_selection_requires_exactly_6"],
    });
    expect(validateSeasonClubSelection(["A", "B", "C", "D", "E", "A"], eligibleClubIds)).toEqual({
      ok: false,
      errors: ["season_selection_has_duplicates"],
    });
    expect(validateSeasonClubSelection(["A", "B", "C", "D", "E", "Z"], eligibleClubIds)).toEqual({
      ok: false,
      errors: ["season_selection_has_ineligible_club"],
    });
  });

  it("adapts RPC state without exposing private club data", () => {
    const state = adaptSeasonRpcState({
      operational_status: "waiting_for_clubs",
      eligible_count: 4,
      required_count: 6,
      missing_count: 2,
      active_season: null,
      current_round: null,
      next_round: null,
      previous_round: null,
    });

    expect(state.waitingMessage).toBe("4 de 6 clubes confirmados. Faltam 2.");
    expect(state.canStartSeason).toBe(false);
  });

  it("formats standings rows from official RPC fields", () => {
    expect(
      formatStandingsRow({
        position: 1,
        club_name: "Bagres FC",
        played: 10,
        points: 22,
        wins: 7,
        draws: 1,
        losses: 2,
        goals_for: 21,
        goals_against: 9,
        goal_difference: 12,
      }),
    ).toEqual({
      position: "1",
      club: "Bagres FC",
      played: "10",
      points: "22",
      wins: "7",
      draws: "1",
      losses: "2",
      goalsFor: "21",
      goalsAgainst: "9",
      goalDifference: "+12",
    });
  });

  it("blocks admin start button for waiting and invalid selection states", () => {
    expect(
      getSeasonAdminActionState({
        operationalStatus: "waiting_for_clubs",
        selectedClubCount: 4,
        configValid: true,
        mutationPending: false,
      }),
    ).toEqual({ disabled: true, reason: "Aguardando 6 clubes elegiveis." });

    expect(
      getSeasonAdminActionState({
        operationalStatus: "ready_to_start",
        selectedClubCount: 5,
        configValid: true,
        mutationPending: false,
      }),
    ).toEqual({ disabled: true, reason: "Selecione exatamente 6 clubes." });
  });
});
