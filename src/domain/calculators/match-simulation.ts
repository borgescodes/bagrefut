import type { Formation, PlayStyle, PlayerPosition } from "../enums";
import { createRng } from "./rng";
import { improvisationMultiplier, styleModifier } from "./multipliers";
import type { PlayerAttributes } from "../types";

export const SIMULATION_VERSION = 1;

const MAX_FORCE = 100;
const MIN_CHANCES = 4;
const MAX_CHANCES = 18;

export interface SimulationSeedParts {
  seasonId: string;
  roundId: string;
  matchId: string;
  simulationVersion: number;
}

export interface SimulationPlayerInput {
  clubPlayerId: string;
  playerId: string;
  clubId: string;
  naturalPosition: PlayerPosition;
  baseOverall: number;
  attributes: PlayerAttributes;
}

export interface SimulationStarter extends SimulationPlayerInput {
  usedPosition: PlayerPosition;
  slotIndex: number;
  effectiveOverall: number;
  improvisationPenalty: number;
}

export interface SimulationLineup {
  clubId: string;
  formation: Formation;
  playStyle: PlayStyle;
  lineupOrigin: "manual" | "automatic";
  starters: SimulationStarter[];
}

export interface AutoLineupInput {
  clubId: string;
  formation: Formation;
  playStyle: PlayStyle;
  eligiblePlayers: readonly SimulationPlayerInput[];
}

export interface FormationModifier {
  attack: number;
  defense: number;
  chanceCreation: number;
  exposure: number;
}

export interface TeamStrength {
  attackStrength: number;
  defenseStrength: number;
  goalkeeperStrength: number;
  overallStrength: number;
}

export interface SimulationTeamInput {
  clubId: string;
  formation: Formation;
  playStyle: PlayStyle;
  lineupOrigin: "manual" | "automatic";
  starters: readonly (SimulationStarter | SimulationPlayerInput)[];
}

export interface MatchSimulationInput {
  seed: string;
  home: SimulationTeamInput;
  away: SimulationTeamInput;
}

export interface MatchStats {
  possession: number;
  chances: number;
  shots: number;
  shotsOnTarget: number;
  saves: number;
  goals: number;
}

export interface MatchSimulationEvent {
  minute: number;
  type: "match_started" | "chance" | "shot" | "save" | "goal" | "halftime" | "match_finished";
  clubId: string | null;
  playerId: string | null;
  homeGoals: number;
  awayGoals: number;
  data: Record<string, number | string | boolean>;
}

export interface MatchSimulationResult {
  simulationVersion: number;
  seed: string;
  homeGoals: number;
  awayGoals: number;
  homeStrength: TeamStrength;
  awayStrength: TeamStrength;
  homeStats: MatchStats;
  awayStats: MatchStats;
  events: MatchSimulationEvent[];
}

export interface MatchRewardConfig {
  win: number;
  draw: number;
  loss: number;
}

export function buildSimulationSeed(parts: SimulationSeedParts): string {
  return `${parts.seasonId}:${parts.roundId}:${parts.matchId}:${parts.simulationVersion}`;
}

export function formationSlots(formation: Formation): PlayerPosition[] {
  switch (formation) {
    case "1-2-1-1":
      return ["GK", "DEF", "DEF", "MID", "ATA"];
    case "1-1-2-1":
      return ["GK", "DEF", "MID", "MID", "ATA"];
    case "1-1-1-2":
      return ["GK", "DEF", "MID", "ATA", "ATA"];
    case "0-2-2-1":
      return ["DEF", "DEF", "MID", "MID", "ATA"];
  }
}

export function formationModifier(formation: Formation): FormationModifier {
  switch (formation) {
    case "1-2-1-1":
      return { attack: 0.98, defense: 1.08, chanceCreation: 0.96, exposure: 0.88 };
    case "1-1-2-1":
      return { attack: 1.02, defense: 0.99, chanceCreation: 1.08, exposure: 1.0 };
    case "1-1-1-2":
      return { attack: 1.1, defense: 0.92, chanceCreation: 1.06, exposure: 1.12 };
    case "0-2-2-1":
      return { attack: 1.05, defense: 0.94, chanceCreation: 1.1, exposure: 1.2 };
  }
}

export function effectiveOverall(
  baseOverall: number,
  natural: PlayerPosition,
  used: PlayerPosition,
): number {
  return clamp(Math.round(baseOverall * improvisationMultiplier(natural, used)), 1, MAX_FORCE);
}

export function selectAutomaticLineup(input: AutoLineupInput): SimulationLineup {
  const remaining = [...input.eligiblePlayers].sort(compareStablePlayer);
  const starters: SimulationStarter[] = [];

  for (const slot of formationSlots(input.formation)) {
    if (remaining.length === 0) throw new Error("lineup_auto_insufficient_players");

    const selected = remaining
      .map((candidate) => {
        const multiplier = improvisationMultiplier(candidate.naturalPosition, slot);
        return {
          candidate,
          multiplier,
          penalty: roundTo(1 - multiplier, 2),
          effective: effectiveOverall(candidate.baseOverall, candidate.naturalPosition, slot),
        };
      })
      .sort((left, right) => {
        const primary =
          Number(right.candidate.naturalPosition === slot) -
          Number(left.candidate.naturalPosition === slot);
        if (primary !== 0) return primary;
        if (left.penalty !== right.penalty) return left.penalty - right.penalty;
        if (left.effective !== right.effective) return right.effective - left.effective;
        if (left.candidate.baseOverall !== right.candidate.baseOverall) {
          return right.candidate.baseOverall - left.candidate.baseOverall;
        }
        return compareStablePlayer(left.candidate, right.candidate);
      })[0];

    if (!selected) throw new Error("lineup_auto_insufficient_players");
    starters.push({
      ...selected.candidate,
      usedPosition: slot,
      slotIndex: starters.filter((starter) => starter.usedPosition === slot).length + 1,
      effectiveOverall: selected.effective,
      improvisationPenalty: selected.penalty,
    });
    remaining.splice(
      remaining.findIndex(
        (candidate) => candidate.clubPlayerId === selected.candidate.clubPlayerId,
      ),
      1,
    );
  }

  return {
    clubId: input.clubId,
    formation: input.formation,
    playStyle: input.playStyle,
    lineupOrigin: "automatic",
    starters,
  };
}

export function calculateTeamStrength(lineup: SimulationTeamInput): TeamStrength {
  const normalized = normalizeLineup(lineup);
  const formation = formationModifier(normalized.formation);
  const style = styleModifier(normalized.playStyle);
  const attackBase = weightedAverage(
    normalized.starters.map((starter) => ({
      value: blendedAttack(starter),
      weight: attackSlotWeight(starter.usedPosition),
    })),
  );
  const defenseBase = weightedAverage(
    normalized.starters.map((starter) => ({
      value: blendedDefense(starter),
      weight: defenseSlotWeight(starter.usedPosition),
    })),
  );
  const goalkeeper = normalized.starters.find((starter) => starter.usedPosition === "GK");
  const goalkeeperStrength = goalkeeper
    ? clamp(
        roundTo(goalkeeper.attributes.goalkeeping * 0.65 + goalkeeper.effectiveOverall * 0.35, 2),
        1,
        MAX_FORCE,
      )
    : 35;
  const attackStrength = clamp(
    roundTo(attackBase * formation.attack * style.attack, 2),
    1,
    MAX_FORCE,
  );
  const defenseStrength = clamp(
    roundTo(defenseBase * formation.defense * style.defense, 2),
    1,
    MAX_FORCE,
  );
  const overallStrength = clamp(
    roundTo(attackStrength * 0.42 + defenseStrength * 0.42 + goalkeeperStrength * 0.16, 2),
    1,
    MAX_FORCE,
  );

  return { attackStrength, defenseStrength, goalkeeperStrength, overallStrength };
}

export function simulateMatch(input: MatchSimulationInput): MatchSimulationResult {
  const home = normalizeLineup(input.home);
  const away = normalizeLineup(input.away);
  const homeStrength = calculateTeamStrength(home);
  const awayStrength = calculateTeamStrength(away);
  const rng = createRng(hashSeedToUint32(input.seed));
  const homeStats = emptyStats();
  const awayStats = emptyStats();
  const events: MatchSimulationEvent[] = [
    {
      minute: 0,
      type: "match_started",
      clubId: null,
      playerId: null,
      homeGoals: 0,
      awayGoals: 0,
      data: {},
    },
  ];
  let homeGoals = 0;
  let awayGoals = 0;

  const homePossessionRaw =
    50 + (homeStrength.overallStrength - awayStrength.overallStrength) * 0.35;
  homeStats.possession = clamp(Math.round(homePossessionRaw), 35, 65);
  awayStats.possession = 100 - homeStats.possession;

  const homeChances = chanceCount(home, homeStrength, away, awayStrength, rng);
  const awayChances = chanceCount(away, awayStrength, home, homeStrength, rng);
  const chanceSchedule = [
    ...scheduledChances("home", homeChances, rng),
    ...scheduledChances("away", awayChances, rng),
  ].sort((left, right) => left.minute - right.minute || (left.side === "home" ? -1 : 1));

  for (const chance of chanceSchedule) {
    if (chance.minute > 45 && !events.some((event) => event.type === "halftime")) {
      events.push(event(45, "halftime", null, null, homeGoals, awayGoals, {}));
    }

    const attackingTeam = chance.side === "home" ? home : away;
    const attackingStrength = chance.side === "home" ? homeStrength : awayStrength;
    const defendingStrength = chance.side === "home" ? awayStrength : homeStrength;
    const stats = chance.side === "home" ? homeStats : awayStats;
    const playerId = pickAttacker(attackingTeam, rng);
    stats.chances += 1;
    events.push(
      event(chance.minute, "chance", attackingTeam.clubId, playerId, homeGoals, awayGoals, {}),
    );

    const shotProbability = clamp(
      0.7 + (attackingStrength.attackStrength - defendingStrength.defenseStrength) / 220,
      0.46,
      0.9,
    );
    if (rng() > shotProbability) continue;

    stats.shots += 1;
    const blocked = rng() < clamp(0.08 + defendingStrength.defenseStrength / 800, 0.08, 0.22);
    events.push(
      event(chance.minute, "shot", attackingTeam.clubId, playerId, homeGoals, awayGoals, {
        blocked,
      }),
    );
    if (blocked) continue;

    const onTargetProbability = clamp(
      0.66 + (attackingStrength.attackStrength - defendingStrength.defenseStrength) / 220,
      0.4,
      0.88,
    );
    if (rng() > onTargetProbability) continue;

    stats.shotsOnTarget += 1;
    const goalProbability = clamp(
      0.5 + (attackingStrength.attackStrength - defendingStrength.goalkeeperStrength) / 230,
      0.18,
      0.7,
    );
    if (rng() < goalProbability) {
      stats.goals += 1;
      if (chance.side === "home") homeGoals += 1;
      else awayGoals += 1;
      events.push(
        event(chance.minute, "goal", attackingTeam.clubId, playerId, homeGoals, awayGoals, {}),
      );
    } else {
      const defendingStats = chance.side === "home" ? awayStats : homeStats;
      defendingStats.saves += 1;
      events.push(
        event(chance.minute, "save", attackingTeam.clubId, playerId, homeGoals, awayGoals, {}),
      );
    }
  }

  if (!events.some((item) => item.type === "halftime")) {
    events.push(event(45, "halftime", null, null, homeGoals, awayGoals, {}));
  }
  events.push(event(90, "match_finished", null, null, homeGoals, awayGoals, {}));

  return {
    simulationVersion: SIMULATION_VERSION,
    seed: input.seed,
    homeGoals,
    awayGoals,
    homeStrength,
    awayStrength,
    homeStats,
    awayStats,
    events: events.sort(
      (left, right) => left.minute - right.minute || eventOrder(left.type) - eventOrder(right.type),
    ),
  };
}

export function calculateMatchRewardCents(input: {
  config: MatchRewardConfig;
  goalsFor: number;
  goalsAgainst: number;
}): number {
  if (input.goalsFor > input.goalsAgainst) return validateReward(input.config.win);
  if (input.goalsFor === input.goalsAgainst) return validateReward(input.config.draw);
  return validateReward(input.config.loss);
}

function normalizeLineup(lineup: SimulationTeamInput): SimulationLineup {
  const slots = formationSlots(lineup.formation);
  const usedCounts = new Map<PlayerPosition, number>();
  return {
    clubId: lineup.clubId,
    formation: lineup.formation,
    playStyle: lineup.playStyle,
    lineupOrigin: lineup.lineupOrigin,
    starters: lineup.starters.map((starter, index) => {
      if ("usedPosition" in starter) return starter;
      const usedPosition = slots[index];
      if (!usedPosition) throw new Error("lineup_invalid_starter_count");
      const slotIndex = (usedCounts.get(usedPosition) ?? 0) + 1;
      usedCounts.set(usedPosition, slotIndex);
      return {
        ...starter,
        usedPosition,
        slotIndex,
        effectiveOverall: effectiveOverall(
          starter.baseOverall,
          starter.naturalPosition,
          usedPosition,
        ),
        improvisationPenalty: roundTo(
          1 - improvisationMultiplier(starter.naturalPosition, usedPosition),
          2,
        ),
      };
    }),
  };
}

function chanceCount(
  attackLineup: SimulationLineup,
  attack: TeamStrength,
  defenseLineup: SimulationLineup,
  defense: TeamStrength,
  rng: () => number,
): number {
  const attackFormation = formationModifier(attackLineup.formation);
  const defenseFormation = formationModifier(defenseLineup.formation);
  const style = styleModifier(attackLineup.playStyle);
  const expected =
    9.4 +
    (attack.attackStrength - defense.defenseStrength) / 8 +
    (style.attack - 1) * 4 +
    (attackFormation.chanceCreation - 1) * 7 +
    (defenseFormation.exposure - 1) * 5;
  const noise = (rng() - 0.5) * 4.2 + (rng() - 0.5) * 2.6;
  return clamp(Math.round(expected + noise), MIN_CHANCES, MAX_CHANCES);
}

function scheduledChances(side: "home" | "away", count: number, rng: () => number) {
  return Array.from({ length: count }, () => ({
    side,
    minute: clamp(1 + Math.floor(rng() * 88), 1, 89),
  }));
}

function pickAttacker(lineup: SimulationLineup, rng: () => number): string {
  const weighted = lineup.starters.map((starter) => ({
    playerId: starter.playerId,
    weight:
      starter.usedPosition === "ATA"
        ? 4
        : starter.usedPosition === "MID"
          ? 3
          : starter.usedPosition === "DEF"
            ? 1.4
            : 0.3,
  }));
  const total = weighted.reduce((sum, entry) => sum + entry.weight, 0);
  let roll = rng() * total;
  for (const entry of weighted) {
    roll -= entry.weight;
    if (roll <= 0) return entry.playerId;
  }
  return weighted.at(-1)?.playerId ?? lineup.starters[0]?.playerId ?? "";
}

function blendedAttack(starter: SimulationStarter): number {
  const attrs =
    starter.attributes.finishing * 0.34 +
    starter.attributes.passing * 0.24 +
    starter.attributes.dribbling * 0.22 +
    starter.attributes.velocity * 0.2;
  return attrs * 0.58 + starter.effectiveOverall * 0.42;
}

function blendedDefense(starter: SimulationStarter): number {
  const attrs =
    starter.attributes.defending * 0.42 +
    starter.attributes.physical * 0.26 +
    starter.attributes.velocity * 0.16 +
    starter.attributes.passing * 0.16;
  return attrs * 0.58 + starter.effectiveOverall * 0.42;
}

function attackSlotWeight(position: PlayerPosition): number {
  switch (position) {
    case "GK":
      return 0.05;
    case "DEF":
      return 0.35;
    case "MID":
      return 0.9;
    case "ATA":
      return 1.15;
  }
}

function defenseSlotWeight(position: PlayerPosition): number {
  switch (position) {
    case "GK":
      return 0.1;
    case "DEF":
      return 1.15;
    case "MID":
      return 0.7;
    case "ATA":
      return 0.25;
  }
}

function weightedAverage(entries: readonly { value: number; weight: number }[]): number {
  const totalWeight = entries.reduce((sum, entry) => sum + entry.weight, 0);
  if (totalWeight <= 0) return 1;
  return entries.reduce((sum, entry) => sum + entry.value * entry.weight, 0) / totalWeight;
}

function emptyStats(): MatchStats {
  return { possession: 50, chances: 0, shots: 0, shotsOnTarget: 0, saves: 0, goals: 0 };
}

function event(
  minute: number,
  type: MatchSimulationEvent["type"],
  clubId: string | null,
  playerId: string | null,
  homeGoals: number,
  awayGoals: number,
  data: Record<string, number | string | boolean>,
): MatchSimulationEvent {
  return { minute, type, clubId, playerId, homeGoals, awayGoals, data };
}

function eventOrder(type: MatchSimulationEvent["type"]): number {
  const order: Record<MatchSimulationEvent["type"], number> = {
    match_started: 0,
    chance: 1,
    shot: 2,
    save: 3,
    goal: 4,
    halftime: 5,
    match_finished: 6,
  };
  return order[type];
}

function compareStablePlayer(left: SimulationPlayerInput, right: SimulationPlayerInput): number {
  return (
    left.clubPlayerId.localeCompare(right.clubPlayerId) ||
    left.playerId.localeCompare(right.playerId) ||
    left.naturalPosition.localeCompare(right.naturalPosition)
  );
}

function validateReward(value: number): number {
  if (!Number.isInteger(value) || value < 0 || value > 10000)
    throw new Error("invalid_match_reward");
  return value;
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

function roundTo(value: number, decimals: number): number {
  const factor = 10 ** decimals;
  return Math.round(value * factor) / factor;
}

function hashSeedToUint32(seed: string): number {
  let hash = 0x811c9dc5;
  for (let index = 0; index < seed.length; index += 1) {
    hash ^= seed.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash >>> 0;
}
