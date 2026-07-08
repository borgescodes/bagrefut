import { describe, expect, it } from "vitest";
import { calculateOverall } from "@/domain/calculators/overall";
import { improvisationMultiplier, styleModifier } from "@/domain/calculators/multipliers";

const flat = (n: number) => ({
  velocity: n,
  finishing: n,
  passing: n,
  dribbling: n,
  defending: n,
  physical: n,
  goalkeeping: n,
});

describe("calculateOverall", () => {
  it("equals the flat value when all attributes are equal", () => {
    for (const pos of ["GK", "DEF", "MID", "ATA"] as const) {
      expect(calculateOverall(pos, flat(65))).toBe(65);
    }
  });
  it("weights goalkeeping heavily for GK", () => {
    const attrs = { ...flat(40), goalkeeping: 90 };
    expect(calculateOverall("GK", attrs)).toBeGreaterThan(calculateOverall("DEF", attrs));
  });
  it("weights finishing heavily for ATA", () => {
    const attrs = { ...flat(40), finishing: 90 };
    expect(calculateOverall("ATA", attrs)).toBeGreaterThan(calculateOverall("DEF", attrs));
  });
  it("matches known weighted vectors for every position", () => {
    const attrs = {
      velocity: 80,
      finishing: 70,
      passing: 60,
      dribbling: 50,
      defending: 40,
      physical: 30,
      goalkeeping: 20,
    };
    expect(calculateOverall("GK", attrs)).toBe(32);
    expect(calculateOverall("DEF", attrs)).toBe(47);
    expect(calculateOverall("MID", attrs)).toBe(55);
    expect(calculateOverall("ATA", attrs)).toBe(63);
  });
});

describe("improvisationMultiplier", () => {
  it("returns 1.0 when player and slot match", () => {
    expect(improvisationMultiplier("MID", "MID")).toBe(1.0);
  });
  it("returns 0.85 for adjacent positions", () => {
    expect(improvisationMultiplier("DEF", "MID")).toBe(0.85);
    expect(improvisationMultiplier("MID", "ATA")).toBe(0.85);
  });
  it("returns 0.7 for far positions", () => {
    expect(improvisationMultiplier("DEF", "ATA")).toBe(0.7);
  });
  it("returns 0.55 whenever a non-GK plays GK or vice versa", () => {
    expect(improvisationMultiplier("DEF", "GK")).toBe(0.55);
    expect(improvisationMultiplier("ATA", "GK")).toBe(0.55);
    expect(improvisationMultiplier("GK", "MID")).toBe(0.55);
  });
});

describe("styleModifier", () => {
  it("balanced is neutral", () => {
    expect(styleModifier("balanced")).toEqual({ attack: 1, defense: 1 });
  });
  it("offensive boosts attack, drops defense", () => {
    const m = styleModifier("offensive");
    expect(m.attack).toBeCloseTo(1.1);
    expect(m.defense).toBeCloseTo(0.9);
  });
  it("defensive boosts defense, drops attack", () => {
    const m = styleModifier("defensive");
    expect(m.attack).toBeCloseTo(0.9);
    expect(m.defense).toBeCloseTo(1.1);
  });
});
