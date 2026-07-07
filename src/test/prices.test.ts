import { describe, expect, it } from "vitest";
import {
  rarityBand,
  referencePriceCents,
  systemBuyPriceCents,
  systemSellPriceCents,
} from "@/domain/calculators/prices";

describe("rarity bands and reference prices", () => {
  it("respects the peba band (R$ 0,50 - R$ 5,00)", () => {
    const b = rarityBand("peba");
    expect(b.min).toBe(50);
    expect(b.max).toBe(500);
    expect(referencePriceCents("peba", 40)).toBe(50);
    expect(referencePriceCents("peba", 59)).toBe(500);
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
    expect(referencePriceCents("pika", 89)).toBe(10000);
  });
  it("system buys at 50% and sells at 100%", () => {
    expect(systemBuyPriceCents(1000)).toBe(500);
    expect(systemSellPriceCents(1000)).toBe(1000);
  });
});
