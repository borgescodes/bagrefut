import type { DatabasePlayerRecord, PlayerCardData, PlayerCardStat } from "./types";
import { formatSectorName } from "@/lib/display-labels";

const STAT_MIN = 0;
const STAT_MAX = 99;

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const PLAYER_POSITIONS = ["GK", "DEF", "MID", "ATA"] as const;
const PLAYER_RARITIES = ["peba", "paia", "pika"] as const;

/** Faixas válidas de players.code por posição (GK01-GK12, DEF01-DEF18, ...). */
const PLAYER_CODE_RANGES: Record<(typeof PLAYER_POSITIONS)[number], number> = {
  GK: 12,
  DEF: 18,
  MID: 18,
  ATA: 12,
};

const PLAYER_CODE_PATTERN = /^(GK|DEF|MID|ATA)(\d{2})$/;

function clampStat(value: number): number {
  if (!Number.isFinite(value)) return STAT_MIN;
  return Math.min(STAT_MAX, Math.max(STAT_MIN, Math.round(value)));
}

function normalizePlayerId(id: string): string {
  const normalized = id.trim().toLowerCase();
  if (!UUID_PATTERN.test(normalized)) {
    throw new Error(`players.id inválido: ${id}`);
  }
  return normalized;
}

/**
 * Normaliza players.code: trim + uppercase e valida contra as faixas
 * oficiais (GK01-GK12, DEF01-DEF18, MID01-MID18, ATA01-ATA12).
 * Rejeita UUID e qualquer formato fora do padrão.
 */
export function normalizePlayerCode(code: string): string {
  const normalized = code.trim().toUpperCase();
  if (UUID_PATTERN.test(normalized)) {
    throw new Error(`players.code não pode ser UUID: ${code}`);
  }
  const match = PLAYER_CODE_PATTERN.exec(normalized);
  if (!match) {
    throw new Error(`Código de jogador inválido: ${code}`);
  }
  const position = match[1] as (typeof PLAYER_POSITIONS)[number];
  const index = Number(match[2]);
  if (index < 1 || index > PLAYER_CODE_RANGES[position]) {
    throw new Error(`Código de jogador fora da faixa: ${code}`);
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
    code: normalizePlayerCode(row.code),
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
 * Caminho do asset: /players/<players.code>.webp — sempre o code
 * (ex.: ATA12), nunca players.id. Lança para UUID ou código malformado.
 */
export function playerImagePath(playerCode: string): string {
  return `/players/${normalizePlayerCode(playerCode)}.webp`;
}

/**
 * Iniciais derivadas de players.name para o fallback visual sem foto.
 * Nunca usa players.code.
 */
export function playerInitials(name: string): string {
  const words = name.trim().split(/\s+/).filter(Boolean);
  if (words.length === 0) return "?";
  if (words.length === 1) return words[0].slice(0, 2).toLocaleUpperCase("pt-BR");
  return (words[0][0] + words[words.length - 1][0]).toLocaleUpperCase("pt-BR");
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
