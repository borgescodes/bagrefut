import type { PlayerPosition, PlayerRarity } from "../enums";
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

const POSITION_MULTIPLIERS: Record<PlayerPosition, number> = {
  GK: 0.9,
  DEF: 0.95,
  MID: 1,
  ATA: 1.1,
};

const TRAINING_COSTS: Record<PlayerRarity, number> = {
  peba: 25,
  paia: 75,
  pika: 150,
};

export function rarityBand(rarity: PlayerRarity): RarityBand {
  return BANDS[rarity];
}

/**
 * Reference price in cents based on rarity and overall.
 * Deterministic: same inputs always yield the same output.
 */
export function referencePriceCents(
  rarity: PlayerRarity,
  overall: number,
  position: PlayerPosition,
): number {
  const { min, max } = BANDS[rarity];
  const overallBand = overallBandForRarity(rarity);
  const clamped = Math.max(overallBand.min, Math.min(overallBand.max, overall));
  const t = (clamped - overallBand.min) / (overallBand.max - overallBand.min || 1);
  const interpolated = min + t * (max - min);
  const positioned = Math.round(interpolated * POSITION_MULTIPLIERS[position]);
  return Math.min(MAX_PRICE_CENTS, Math.max(min, Math.min(max, positioned)));
}

function overallBandForRarity(rarity: PlayerRarity): RarityBand {
  switch (rarity) {
    case "peba":
      return { min: 40, max: 59 };
    case "paia":
      return { min: 60, max: 74 };
    case "pika":
      return { min: 75, max: 89 };
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

export function trainingCostCents(rarity: PlayerRarity): number {
  return TRAINING_COSTS[rarity];
}

export function positionPriceMultiplier(position: PlayerPosition): number {
  return POSITION_MULTIPLIERS[position];
}
