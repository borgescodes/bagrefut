import type { PlayStyle, PlayerPosition } from "../enums";

/**
 * Improvisation multiplier: how much of a player's overall counts
 * when they play in slotPosition instead of their natural playerPosition.
 */
export function improvisationMultiplier(
  playerPosition: PlayerPosition,
  slotPosition: PlayerPosition,
): number {
  if (playerPosition === slotPosition) return 1.0;

  // Anyone other than a GK slotted at GK is heavily improvised.
  if (slotPosition === "GK") return 0.55;
  // A GK playing outfield is also heavily improvised.
  if (playerPosition === "GK") return 0.55;

  const near: Record<PlayerPosition, PlayerPosition[]> = {
    GK: [],
    DEF: ["MID"],
    MID: ["DEF", "ATA"],
    ATA: ["MID"],
  };

  return near[playerPosition].includes(slotPosition) ? 0.85 : 0.7;
}

export interface StyleModifier {
  attack: number;
  defense: number;
}

export function styleModifier(style: PlayStyle): StyleModifier {
  switch (style) {
    case "offensive":
      return { attack: 1.1, defense: 0.9 };
    case "defensive":
      return { attack: 0.9, defense: 1.1 };
    case "balanced":
    default:
      return { attack: 1.0, defense: 1.0 };
  }
}

export const HOME_ADVANTAGE = 1.03;
export const RANDOMNESS_RANGE = 0.08;
