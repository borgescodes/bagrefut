import type { PlayerRarity } from "../enums";
import { MAX_PRICE_CENTS } from "../rules/validators";

interface RarityBand {
  min: number;
  max: number;
}

const BANDS: Record<PlayerRarity, RarityBand> = {
  peba: { min: 50, max: 500 },
  paia: { min: 501, max: 2500 },
  pika: { min: 2501, max: MAX_PRICE_CENTS },
};

export function rarityBand(rarity: PlayerRarity): RarityBand {
  return BANDS[rarity];
}

/**
 * Reference price in cents based on rarity and overall.
 * Deterministic: same inputs always yield the same output.
 */
export function referencePriceCents(rarity: PlayerRarity, overall: number): number {
  const { min, max } = BANDS[rarity];
  const overallBand = overallBandForRarity(rarity);
  const clamped = Math.max(overallBand.min, Math.min(overallBand.max, overall));
  const t = (clamped - overallBand.min) / (overallBand.max - overallBand.min || 1);
  return Math.round(min + t * (max - min));
}

function overallBandForRarity(rarity: PlayerRarity): RarityBand {
  switch (rarity) {
    case "peba": return { min: 40, max: 59 };
    case "paia": return { min: 60, max: 74 };
    case "pika": return { min: 75, max: 89 };
  }
}

/** System buys cards at 50% of reference price. */
export function systemBuyPriceCents(referenceCents: number): number {
  return Math.floor(referenceCents / 2);
}

/** System sells cards at 100% of reference price. */
export function systemSellPriceCents(referenceCents: number): number {
  return referenceCents;
}
