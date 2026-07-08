import { describe, expect, it } from "vitest";
import { createRng, shuffleWithSeed } from "@/domain/calculators/rng";

describe("createRng", () => {
  it("produces the same sequence for the same seed", () => {
    const a = createRng(42);
    const b = createRng(42);
    for (let i = 0; i < 10; i++) expect(a()).toBe(b());
  });
  it("produces different sequences for different seeds", () => {
    const a = createRng(1);
    const b = createRng(2);
    const seqA = Array.from({ length: 5 }, () => a());
    const seqB = Array.from({ length: 5 }, () => b());
    expect(seqA).not.toEqual(seqB);
  });
  it("always returns values in the [0, 1) range", () => {
    const rng = createRng(20260708);
    const values = Array.from({ length: 100 }, () => rng());

    for (const value of values) {
      expect(value).toBeGreaterThanOrEqual(0);
      expect(value).toBeLessThan(1);
    }
  });
});

describe("shuffleWithSeed", () => {
  it("produces the same permutation for the same seed", () => {
    const items = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    expect(shuffleWithSeed(items, 123)).toEqual(shuffleWithSeed(items, 123));
  });
  it("does not mutate the input", () => {
    const items = [1, 2, 3];
    const copy = items.slice();
    shuffleWithSeed(items, 7);
    expect(items).toEqual(copy);
  });
});
