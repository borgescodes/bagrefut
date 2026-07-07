import type { PlayerAttributeKey, PlayerPosition } from "../enums";
import type { PlayerAttributes } from "../types";

/**
 * Weighted overall calculation per position.
 * Weights are integers that sum to 100 for readability.
 */
const WEIGHTS: Record<PlayerPosition, Partial<Record<PlayerAttributeKey, number>>> = {
  GK: { goalkeeping: 55, defending: 15, physical: 15, passing: 10, velocity: 5 },
  DEF: { defending: 40, physical: 25, velocity: 15, passing: 15, dribbling: 5 },
  MID: { passing: 30, dribbling: 25, velocity: 15, physical: 15, defending: 10, finishing: 5 },
  ATA: { finishing: 40, velocity: 20, dribbling: 20, physical: 10, passing: 10 },
};

export function calculateOverall(position: PlayerPosition, attrs: PlayerAttributes): number {
  const weights = WEIGHTS[position];
  let total = 0;
  let denom = 0;
  for (const [key, weight] of Object.entries(weights) as [PlayerAttributeKey, number][]) {
    total += (attrs[key] ?? 0) * weight;
    denom += weight;
  }
  if (denom === 0) return 0;
  return Math.round(total / denom);
}

export function positionWeights(position: PlayerPosition): Readonly<Partial<Record<PlayerAttributeKey, number>>> {
  return WEIGHTS[position];
}
