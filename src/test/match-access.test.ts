import { describe, expect, it } from "vitest";
import {
  canRequestMatchEvents,
  mapMatchEventsErrorMessage,
  shouldFetchMatchEvents,
} from "@/lib/match-access";
import type { MatchScoreSummary } from "@/domain/types";

const summary: MatchScoreSummary = {
  match_id: "00000000-0000-0000-0000-000000000001",
  status: "finished",
  round_number: 1,
  competition_name: "Bagreleirao",
  starts_at: "2026-07-08T12:00:00Z",
  home_club_id: "00000000-0000-0000-0000-000000000101",
  home_club_name: "Mandante",
  home_club_abbreviation: "MAN",
  home_club_badge_path: "/badges/home.png",
  away_club_id: "00000000-0000-0000-0000-000000000102",
  away_club_name: "Visitante",
  away_club_abbreviation: "VIS",
  away_club_badge_path: "/badges/away.png",
  home_goals: 2,
  away_goals: 1,
  final_result: "home_win",
};

describe("match event access helpers", () => {
  it("allows approved admin to request events for any match", () => {
    expect(canRequestMatchEvents({ summary, myClubId: null, isAdmin: true })).toBe(true);
  });

  it("allows the home club owner to request events", () => {
    expect(
      canRequestMatchEvents({
        summary,
        myClubId: summary.home_club_id,
        isAdmin: false,
      }),
    ).toBe(true);
  });

  it("allows the away club owner to request events", () => {
    expect(
      canRequestMatchEvents({
        summary,
        myClubId: summary.away_club_id,
        isAdmin: false,
      }),
    ).toBe(true);
  });

  it("does not request events for unrelated matches", () => {
    expect(
      canRequestMatchEvents({
        summary,
        myClubId: "00000000-0000-0000-0000-000000000999",
        isAdmin: false,
      }),
    ).toBe(false);
    expect(shouldFetchMatchEvents({ summary, myClubId: null, isAdmin: false })).toBe(false);
  });

  it("maps forbidden match events errors to pt-BR", () => {
    expect(mapMatchEventsErrorMessage(new Error("match_events_forbidden"))).toBe(
      "Eventos detalhados disponiveis somente para partidas do seu clube.",
    );
  });
});
