import { describe, expect, it } from "vitest";
import {
  rarityBand,
  referencePriceCents,
  systemBuyPriceCents,
  systemSellPriceCents,
  trainingCostCents,
} from "@/domain/calculators/prices";

describe("rarity bands and reference prices", () => {
  it("respects the peba band (R$ 0,50 - R$ 5,00)", () => {
    const b = rarityBand("peba");
    expect(b.min).toBe(50);
    expect(b.max).toBe(500);
    expect(referencePriceCents("peba", 40, "MID")).toBe(50);
    expect(referencePriceCents("peba", 59, "MID")).toBe(500);
  });
  it("respects the paia band (R$ 5,01 - R$ 25,00)", () => {
    const b = rarityBand("paia");
    expect(b.min).toBe(501);
    expect(b.max).toBe(2500);
  });
  it("respects the pika band (R$ 25,01 - R$ 100,00)", () => {
    const b = rarityBand("pika");
    expect(b.min).toBe(2501);
    expect(b.max).toBe(10000);
    expect(referencePriceCents("pika", 89, "MID")).toBe(10000);
  });
  it("applies exact position multipliers after interpolation", () => {
    expect(referencePriceCents("paia", 67, "GK")).toBe(1350);
    expect(referencePriceCents("paia", 67, "DEF")).toBe(1425);
    expect(referencePriceCents("paia", 67, "MID")).toBe(1501);
    expect(referencePriceCents("paia", 67, "ATA")).toBe(1651);
  });
  it("clamps multiplied prices inside rarity bands and global cap", () => {
    expect(referencePriceCents("peba", 40, "GK")).toBe(50);
    expect(referencePriceCents("peba", 59, "ATA")).toBe(500);
    expect(referencePriceCents("pika", 89, "ATA")).toBe(10000);
  });
  it("system buys at 50% and sells at 100%", () => {
    expect(systemBuyPriceCents(1001)).toBe(500);
    expect(systemSellPriceCents(1001)).toBe(1001);
  });
  it("returns fixed training costs by rarity", () => {
    expect(trainingCostCents("peba")).toBe(25);
    expect(trainingCostCents("paia")).toBe(75);
    expect(trainingCostCents("pika")).toBe(150);
  });
});
