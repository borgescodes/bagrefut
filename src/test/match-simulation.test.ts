import { describe, expect, it } from "vitest";
import type { Formation, PlayStyle, PlayerPosition } from "@/domain/enums";
import type { PlayerAttributes } from "@/domain/types";
import {
  SIMULATION_VERSION,
  buildSimulationSeed,
  calculateMatchRewardCents,
  calculateTeamStrength,
  formationModifier,
  selectAutomaticLineup,
  simulateMatch,
} from "@/domain/calculators/match-simulation";

const baseAttributes: PlayerAttributes = {
  velocity: 60,
  finishing: 60,
  passing: 60,
  dribbling: 60,
  defending: 60,
  physical: 60,
  goalkeeping: 60,
};

function player(
  id: string,
  position: PlayerPosition,
  overall: number,
  attrs: Partial<PlayerAttributes> = {},
) {
  return {
    clubPlayerId: id,
    playerId: `player-${id}`,
    clubId: "club-a",
    naturalPosition: position,
    baseOverall: overall,
    attributes: { ...baseAttributes, ...attrs },
  };
}

const balancedFive = [
  player("a-gk", "GK", 68, { goalkeeping: 78 }),
  player("a-def", "DEF", 68, { defending: 76 }),
  player("a-def-2", "DEF", 64, { defending: 70 }),
  player("a-mid", "MID", 68, { passing: 76, dribbling: 72 }),
  player("a-ata", "ATA", 68, { finishing: 76 }),
];

const superiorFive = [
  player("b-gk", "GK", 82, { goalkeeping: 90 }),
  player("b-def", "DEF", 82, { defending: 88 }),
  player("b-def-2", "DEF", 80, { defending: 86 }),
  player("b-mid", "MID", 84, { passing: 90, dribbling: 86 }),
  player("b-ata", "ATA", 86, { finishing: 92 }),
];

function team(clubId: string, style: PlayStyle = "balanced", formation: Formation = "1-2-1-1") {
  const source = clubId === "home" ? balancedFive : balancedFive;
  return {
    clubId,
    formation,
    playStyle: style,
    lineupOrigin: "manual" as const,
    starters: source.map((entry) => ({ ...entry, clubId })),
  };
}

describe("buildSimulationSeed", () => {
  it("uses immutable ids and simulator version", () => {
    expect(
      buildSimulationSeed({
        seasonId: "season-1",
        roundId: "round-1",
        matchId: "match-1",
        simulationVersion: SIMULATION_VERSION,
      }),
    ).toBe("season-1:round-1:match-1:1");
  });
});

describe("selectAutomaticLineup", () => {
  it("fills every formation slot deterministically without duplicating players", () => {
    const roster = [
      player("mid-2", "MID", 74),
      player("ata-1", "ATA", 70),
      player("def-1", "DEF", 72),
      player("gk-1", "GK", 67),
      player("def-2", "DEF", 69),
      player("mid-1", "MID", 76),
    ];

    const lineup = selectAutomaticLineup({
      clubId: "club-a",
      formation: "1-1-2-1",
      playStyle: "balanced",
      eligiblePlayers: roster,
    });

    expect(lineup.lineupOrigin).toBe("automatic");
    expect(lineup.starters.map((entry) => `${entry.usedPosition}:${entry.slotIndex}`)).toEqual([
      "GK:1",
      "DEF:1",
      "MID:1",
      "MID:2",
      "ATA:1",
    ]);
    expect(new Set(lineup.starters.map((entry) => entry.clubPlayerId)).size).toBe(5);
    expect(lineup.starters.map((entry) => entry.clubPlayerId)).toEqual([
      "gk-1",
      "def-1",
      "mid-1",
      "mid-2",
      "ata-1",
    ]);
  });

  it("falls back to the lowest improvisation penalty before effective OVR", () => {
    const lineup = selectAutomaticLineup({
      clubId: "club-a",
      formation: "1-1-1-2",
      playStyle: "balanced",
      eligiblePlayers: [
        player("gk-1", "GK", 60),
        player("def-1", "DEF", 60),
        player("mid-1", "MID", 60),
        player("mid-2", "MID", 59),
        player("ata-1", "ATA", 58),
      ],
    });

    const attackingSlots = lineup.starters.filter((entry) => entry.usedPosition === "ATA");
    expect(attackingSlots.map((entry) => entry.clubPlayerId)).toEqual(["ata-1", "mid-2"]);
    expect(attackingSlots[1]?.improvisationPenalty).toBe(0.15);
    expect(attackingSlots[1]?.effectiveOverall).toBe(50);
  });

  it("throws an explicit error when a club cannot fill five slots", () => {
    expect(() =>
      selectAutomaticLineup({
        clubId: "club-a",
        formation: "1-2-1-1",
        playStyle: "balanced",
        eligiblePlayers: balancedFive.slice(0, 4),
      }),
    ).toThrow("lineup_auto_insufficient_players");
  });
});

describe("calculateTeamStrength", () => {
  it("documents bounded force ranges and applies formation, style, and improvisation", () => {
    const automatic = selectAutomaticLineup({
      clubId: "club-a",
      formation: "0-2-2-1",
      playStyle: "offensive",
      eligiblePlayers: balancedFive,
    });

    const strength = calculateTeamStrength(automatic);

    expect(strength.attackStrength).toBeGreaterThan(0);
    expect(strength.attackStrength).toBeLessThanOrEqual(100);
    expect(strength.defenseStrength).toBeGreaterThan(0);
    expect(strength.defenseStrength).toBeLessThanOrEqual(100);
    expect(strength.goalkeeperStrength).toBeGreaterThanOrEqual(0);
    expect(strength.goalkeeperStrength).toBeLessThanOrEqual(100);
    expect(strength.overallStrength).toBeGreaterThan(0);
    expect(strength.overallStrength).toBeLessThanOrEqual(100);
  });

  it("formation modifiers change attack, defense, chance volume, and exposure", () => {
    expect(formationModifier("1-1-1-2").attack).toBeGreaterThan(
      formationModifier("1-2-1-1").attack,
    );
    expect(formationModifier("1-2-1-1").defense).toBeGreaterThan(
      formationModifier("1-1-1-2").defense,
    );
    expect(formationModifier("0-2-2-1").exposure).toBeGreaterThan(
      formationModifier("1-2-1-1").exposure,
    );
    expect(formationModifier("1-1-2-1").chanceCreation).toBeGreaterThan(
      formationModifier("1-2-1-1").chanceCreation,
    );
  });
});

describe("simulateMatch", () => {
  it("returns exactly the same score, events, minutes, and stats for the same seed", () => {
    const input = {
      seed: "season:round:match:1",
      home: team("home"),
      away: team("away"),
    };

    expect(simulateMatch(input)).toEqual(simulateMatch(input));
  });

  it("lets a different seed produce a different deterministic event stream", () => {
    const common = {
      home: team("home"),
      away: team("away"),
    };

    expect(simulateMatch({ ...common, seed: "seed-a" }).events).not.toEqual(
      simulateMatch({ ...common, seed: "seed-b" }).events,
    );
  });

  it("keeps score, ordered events, and statistics internally consistent", () => {
    const result = simulateMatch({
      seed: "consistency-seed",
      home: team("home"),
      away: team("away"),
    });

    const homeGoalEvents = result.events.filter(
      (event) => event.type === "goal" && event.clubId === "home",
    );
    const awayGoalEvents = result.events.filter(
      (event) => event.type === "goal" && event.clubId === "away",
    );

    expect(result.homeGoals).toBe(homeGoalEvents.length);
    expect(result.awayGoals).toBe(awayGoalEvents.length);
    expect(result.events[0]?.type).toBe("match_started");
    expect(result.events.at(-1)?.type).toBe("match_finished");
    expect(result.events.every((event) => event.minute >= 0 && event.minute <= 90)).toBe(true);
    expect(result.events.map((event) => event.minute)).toEqual(
      [...result.events].map((event) => event.minute).sort((a, b) => a - b),
    );

    for (const stats of [result.homeStats, result.awayStats]) {
      expect(stats.shotsOnTarget).toBeGreaterThanOrEqual(stats.goals);
      expect(stats.shots).toBeGreaterThanOrEqual(stats.shotsOnTarget);
      expect(stats.chances).toBeGreaterThanOrEqual(stats.shots);
    }
    expect(result.awayStats.saves + result.homeStats.goals).toBe(result.homeStats.shotsOnTarget);
    expect(result.homeStats.saves + result.awayStats.goals).toBe(result.awayStats.shotsOnTarget);
    expect(result.homeStats.possession + result.awayStats.possession).toBe(100);
  });

  it("superior teams win more often but not always across a fixed seed set", () => {
    const seeds = Array.from({ length: 2000 }, (_, index) => `superior-${index}`);
    const totals = seeds.reduce(
      (acc, seed) => {
        const result = simulateMatch({
          seed,
          home: {
            ...team("home"),
            starters: superiorFive.map((entry) => ({ ...entry, clubId: "home" })),
          },
          away: team("away"),
        });
        if (result.homeGoals > result.awayGoals) acc.homeWins += 1;
        if (result.homeGoals === result.awayGoals) acc.draws += 1;
        acc.goals += result.homeGoals + result.awayGoals;
        acc.extremeScores += result.homeGoals + result.awayGoals >= 8 ? 1 : 0;
        return acc;
      },
      { homeWins: 0, draws: 0, goals: 0, extremeScores: 0 },
    );

    expect(totals.homeWins / seeds.length).toBeGreaterThan(0.5);
    expect(totals.homeWins / seeds.length).toBeLessThan(0.9);
    expect(totals.draws / seeds.length).toBeGreaterThan(0.08);
    expect(totals.goals / seeds.length).toBeGreaterThan(1.8);
    expect(totals.goals / seeds.length).toBeLessThan(4.8);
    expect(totals.extremeScores / seeds.length).toBeLessThan(0.04);
  });

  it("equal teams stay balanced and styles alter profile without guaranteeing victory", () => {
    const seeds = Array.from({ length: 2000 }, (_, index) => `equal-${index}`);
    const balanced = seeds.reduce(
      (acc, seed) => {
        const result = simulateMatch({ seed, home: team("home"), away: team("away") });
        if (result.homeGoals > result.awayGoals) acc.homeWins += 1;
        if (result.awayGoals > result.homeGoals) acc.awayWins += 1;
        return acc;
      },
      { homeWins: 0, awayWins: 0 },
    );

    const styleProfile = seeds.reduce(
      (acc, seed) => {
        const offensive = simulateMatch({
          seed,
          home: team("home", "offensive"),
          away: team("away", "defensive"),
        });
        acc.offensiveChances += offensive.homeStats.chances;
        acc.defensiveChances += offensive.awayStats.chances;
        if (offensive.awayGoals > offensive.homeGoals) acc.defensiveWins += 1;
        return acc;
      },
      { offensiveChances: 0, defensiveChances: 0, defensiveWins: 0 },
    );

    const balanceGap = Math.abs(balanced.homeWins - balanced.awayWins) / seeds.length;
    expect(balanceGap).toBeLessThan(0.08);
    expect(styleProfile.offensiveChances).toBeGreaterThan(styleProfile.defensiveChances);
    expect(styleProfile.defensiveWins).toBeGreaterThan(0);
  });
});

describe("calculateMatchRewardCents", () => {
  it("pays win, draw, and loss rewards as configured with integer cents", () => {
    const config = { win: 75, draw: 25, loss: 0 };

    expect(calculateMatchRewardCents({ config, goalsFor: 2, goalsAgainst: 1 })).toBe(75);
    expect(calculateMatchRewardCents({ config, goalsFor: 1, goalsAgainst: 1 })).toBe(25);
    expect(calculateMatchRewardCents({ config, goalsFor: 0, goalsAgainst: 1 })).toBe(0);
  });
});
