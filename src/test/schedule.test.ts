import { describe, expect, it } from "vitest";
import { generateSchedule } from "@/domain/calculators/schedule";

const clubIds = ["A", "B", "C", "D", "E", "F"];

describe("generateSchedule", () => {
  const schedule = generateSchedule(clubIds);

  it("returns 30 matches across 10 rounds", () => {
    expect(schedule).toHaveLength(30);
    const rounds = new Set(schedule.map((m) => m.round));
    expect(rounds.size).toBe(10);
  });

  it("has each club playing exactly once per round", () => {
    for (let r = 1; r <= 10; r++) {
      const matches = schedule.filter((m) => m.round === r);
      expect(matches).toHaveLength(3);
      const clubsInRound = new Set<string>();
      for (const m of matches) {
        expect(clubsInRound.has(m.home)).toBe(false);
        expect(clubsInRound.has(m.away)).toBe(false);
        clubsInRound.add(m.home);
        clubsInRound.add(m.away);
      }
      expect(clubsInRound.size).toBe(6);
    }
  });

  it("mirrors home/away in returno vs turno", () => {
    const turno = schedule.filter((m) => m.round <= 5);
    const returno = schedule.filter((m) => m.round >= 6);
    // Every returno pair should be the mirror of some turno pair
    for (const rm of returno) {
      const match = turno.find((tm) => tm.home === rm.away && tm.away === rm.home);
      expect(match, `no mirror for ${rm.home} x ${rm.away}`).toBeTruthy();
    }
  });

  it("throws when not exactly 6 clubs", () => {
    expect(() => generateSchedule(["A", "B", "C"])).toThrow();
  });

  it("is deterministic for the same input", () => {
    const a = generateSchedule(clubIds);
    const b = generateSchedule(clubIds);
    expect(a).toEqual(b);
  });
});
