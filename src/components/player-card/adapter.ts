import type { DatabasePlayerRecord, PlayerCardData, PlayerCardStat } from "./types";
import { formatSectorName } from "@/lib/display-labels";

const STAT_MIN = 0;
const STAT_MAX = 99;

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const PLAYER_POSITIONS = ["GK", "DEF", "MID", "ATA"] as const;
const PLAYER_RARITIES = ["peba", "paia", "pika"] as const;

function clampStat(value: number): number {
  if (!Number.isFinite(value)) return STAT_MIN;
  return Math.min(STAT_MAX, Math.max(STAT_MIN, Math.round(value)));
}

function normalizePlayerId(id: string): string {
  const normalized = id.trim().toLowerCase();
  if (!UUID_PATTERN.test(normalized)) {
    throw new Error(`players.id inválido para asset de carta: ${id}`);
  }
  return normalized;
}

function normalizeCode(code: string): string {
  const normalized = code.trim().toUpperCase();
  if (!/^[A-Z0-9_-]+$/.test(normalized)) {
    throw new Error(`Código de jogador inválido: ${code}`);
  }
  return normalized;
}

function normalizeName(name: string): string {
  const normalized = name.trim().replace(/\s+/g, " ");
  if (!normalized) throw new Error("players.name é obrigatório.");
  return normalized;
}

/**
 * Converte linha de public.players para o modelo visual da carta.
 * Nome exibido vem de players.name; troca futura de nomes no banco
 * aparece aqui sem mudança de frontend.
 */
export function playerCardFromDatabase(row: DatabasePlayerRecord): PlayerCardData {
  if (!PLAYER_RARITIES.includes(row.rarity)) {
    throw new Error(`Raridade inválida: ${String(row.rarity)}`);
  }
  if (!PLAYER_POSITIONS.includes(row.position)) {
    throw new Error(`Posição inválida: ${String(row.position)}`);
  }
  return {
    id: normalizePlayerId(row.id),
    code: normalizeCode(row.code),
    name: normalizeName(row.name),
    position: row.position,
    rarity: row.rarity,
    sector: row.sector,
    overall: clampStat(row.overall),
    velocity: clampStat(row.velocity),
    finishing: clampStat(row.finishing),
    passing: clampStat(row.passing),
    dribbling: clampStat(row.dribbling),
    defending: clampStat(row.defending),
    physical: clampStat(row.physical),
    goalkeeping: clampStat(row.goalkeeping),
  };
}

/**
 * Caminho do asset: /players/<players.id>.webp — sempre o UUID,
 * nunca players.code. Lança se o id não for UUID.
 */
export function playerImagePath(playerId: string): string {
  return `/players/${normalizePlayerId(playerId)}.webp`;
}

/** Formata somente para display; o valor persistido fica intacto. */
export function displaySector(sector: string): string {
  return formatSectorName(sector);
}

/**
 * Grade de 6 atributos na ordem visual da carta.
 * GK troca FIN por GK (goalkeeping) no primeiro slot.
 */
export function playerCardStats(player: PlayerCardData): PlayerCardStat[] {
  const primary: PlayerCardStat =
    player.position === "GK"
      ? { label: "GK", value: player.goalkeeping }
      : { label: "FIN", value: player.finishing };
  return [
    primary,
    { label: "DRI", value: player.dribbling },
    { label: "VEL", value: player.velocity },
    { label: "DEF", value: player.defending },
    { label: "PAS", value: player.passing },
    { label: "PHY", value: player.physical },
  ];
}
