import { createServerFn } from "@tanstack/react-start";
import type { SupabaseClient } from "@supabase/supabase-js";
import { z } from "zod";
import { FORMATIONS, PLAYER_ATTRIBUTE_KEYS, PLAY_STYLES } from "@/domain/enums";
import {
  type LineupPlayerSelection,
  type LineupRosterPlayer,
  type SavedLineupSnapshot,
} from "@/domain/lineup";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import type { Database, Json } from "@/integrations/supabase/types";

type Formation = Database["public"]["Enums"]["formation"];
type PlayStyle = Database["public"]["Enums"]["play_style"];
type PlayerPosition = Database["public"]["Enums"]["player_position"];
type SaveLineupRow = Database["public"]["Functions"]["save_lineup"]["Returns"][number];

export interface SaveLineupInput {
  formation: Formation;
  style: PlayStyle;
  players: readonly LineupPlayerSelection[];
}

export interface SaveLineupRpcArgs {
  _round_id: string;
  _formation: Formation;
  _play_style: PlayStyle;
  _players: Json;
}

export interface SaveLineupResult {
  lineupId: string;
  clubId: string;
  roundId: string;
  formation: Formation;
  style: PlayStyle;
  playerCount: number;
  starterCount: number;
  savedAt: string;
}

export interface SaveLineupRpcClient {
  rpc(
    fn: "save_lineup",
    args: SaveLineupRpcArgs,
  ): PromiseLike<{ data: SaveLineupRow[] | null; error: { message: string } | null }>;
}

export interface LineupRoundSummary {
  id: string;
  roundNumber: number;
  lineupLockAt: string;
  startsAt: string;
  isBlocked: boolean;
}

export interface LineupWorkspace {
  club: { id: string; name: string; abbreviation: string } | null;
  roster: LineupRosterPlayer[];
  round: LineupRoundSummary | null;
  savedLineup: SavedLineupSnapshot | null;
}

const lineupPlayerInput = z.object({
  clubPlayerId: z.string().uuid(),
  slotPosition: z.enum(["GK", "DEF", "MID", "ATA"]),
  slotIndex: z.number().int().min(1).max(10),
  isStarter: z.boolean(),
});

const saveLineupInput = z.object({
  formation: z.enum(FORMATIONS),
  style: z.enum(PLAY_STYLES),
  players: z.array(lineupPlayerInput).min(5).max(10),
});

export function buildSaveLineupRpcArgs(roundId: string, input: SaveLineupInput): SaveLineupRpcArgs {
  return {
    _round_id: roundId,
    _formation: input.formation,
    _play_style: input.style,
    _players: input.players.map((player) => ({
      club_player_id: player.clubPlayerId,
      slot_position: player.slotPosition,
      is_starter: player.isStarter,
      slot_index: player.slotIndex,
    })),
  };
}

export async function saveLineupRpc(
  client: SaveLineupRpcClient,
  roundId: string,
  input: SaveLineupInput,
): Promise<SaveLineupResult> {
  const { data, error } = await client.rpc("save_lineup", buildSaveLineupRpcArgs(roundId, input));
  if (error) throw new Error(mapSaveLineupErrorMessage(error));

  const row = data?.[0];
  if (!row?.lineup_id || !row.club_id || !row.round_id || !row.saved_at) {
    throw new Error("Nao foi possivel confirmar o salvamento da escalacao.");
  }

  return {
    lineupId: row.lineup_id,
    clubId: row.club_id,
    roundId: row.round_id,
    formation: row.formation,
    style: row.play_style,
    playerCount: row.player_count,
    starterCount: row.starter_count,
    savedAt: row.saved_at,
  };
}

export function mapSaveLineupErrorMessage(error: unknown): string {
  const message =
    error instanceof Error
      ? error.message
      : typeof error === "object" &&
          error !== null &&
          "message" in error &&
          typeof error.message === "string"
        ? error.message
        : String(error);
  if (message.includes("lineup_locked")) {
    return "O prazo para editar a escalacao desta rodada ja encerrou.";
  }
  if (message.includes("duplicate_club_player")) {
    return "O mesmo jogador nao pode aparecer duas vezes.";
  }
  if (message.includes("formation_slot_mismatch")) {
    return "A formacao escolhida nao bate com as posicoes preenchidas.";
  }
  if (message.includes("invalid_starter_count") || message.includes("invalid_player_count")) {
    return "A escalacao precisa ter 5 titulares e ate 5 reservas.";
  }
  if (message.includes("club_player_not_owned")) {
    return "A escalacao contem jogador que nao pertence ao seu clube.";
  }
  if (message.includes("club_player_reserved")) {
    return "Um jogador selecionado esta reservado em outra operacao.";
  }
  if (message.includes("round_not_found") || message.includes("season_not_active")) {
    return "Nao ha rodada ativa disponivel para salvar escalacao.";
  }
  if (message.includes("club_not_found")) {
    return "Crie um clube antes de salvar a escalacao.";
  }
  if (message.includes("profile_not_approved")) {
    return "Sua conta ainda nao esta aprovada para salvar escalacao.";
  }
  if (message.includes("unauthenticated")) {
    return "Entre novamente para salvar a escalacao.";
  }
  return "Nao foi possivel salvar a escalacao.";
}

export const getLineupWorkspace = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }): Promise<LineupWorkspace> => {
    const { supabase, userId } = context;
    const { data: club, error: clubError } = await supabase
      .from("clubs")
      .select("id, name, abbreviation, league_id")
      .eq("owner_id", userId)
      .maybeSingle();

    if (clubError) throw new Error(clubError.message);
    if (!club) return { club: null, roster: [], round: null, savedLineup: null };

    const [{ data: rosterRows, error: rosterError }, { data: roundRows, error: roundError }] =
      await Promise.all([
        supabase
          .from("club_players")
          .select(
            `
            id,
            is_reserved,
            players (
              name,
              position,
              overall,
              velocity,
              finishing,
              passing,
              dribbling,
              defending,
              physical,
              goalkeeping
            ),
            club_player_attribute_progress (
              attribute,
              progress,
              updated_at
            )
          `,
          )
          .eq("club_id", club.id)
          .order("acquired_at", { ascending: true }),
        supabase
          .from("rounds")
          .select("id, round_number, lineup_lock_at, starts_at, seasons!inner(status, league_id)")
          .eq("is_processed", false)
          .eq("seasons.status", "active")
          .eq("seasons.league_id", club.league_id)
          .order("starts_at", { ascending: true })
          .limit(1),
      ]);

    if (rosterError) throw new Error(rosterError.message);
    if (roundError) throw new Error(roundError.message);

    const roundRow = roundRows?.[0] ?? null;
    const savedLineup = roundRow
      ? await loadSavedLineup(context.supabase, club.id, roundRow.id)
      : null;

    return {
      club: { id: club.id, name: club.name, abbreviation: club.abbreviation },
      roster: (rosterRows ?? []).map((row) => toRosterPlayer(row)),
      round: roundRow
        ? {
            id: roundRow.id,
            roundNumber: roundRow.round_number,
            lineupLockAt: roundRow.lineup_lock_at,
            startsAt: roundRow.starts_at,
            isBlocked: Date.parse(roundRow.lineup_lock_at) <= Date.now(),
          }
        : null,
      savedLineup,
    };
  });

export const saveLineup = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((data: unknown) => saveLineupInput.parse(data))
  .handler(async ({ data, context }) => {
    const { data: club, error: clubError } = await context.supabase
      .from("clubs")
      .select("id, league_id")
      .eq("owner_id", context.userId)
      .maybeSingle();
    if (clubError) throw new Error(clubError.message);
    if (!club) throw new Error(mapSaveLineupErrorMessage(new Error("club_not_found")));

    const { data: rounds, error: roundError } = await context.supabase
      .from("rounds")
      .select("id, seasons!inner(status, league_id)")
      .eq("is_processed", false)
      .eq("seasons.status", "active")
      .eq("seasons.league_id", club.league_id)
      .order("starts_at", { ascending: true })
      .limit(1);
    if (roundError) throw new Error(roundError.message);

    const roundId = rounds?.[0]?.id;
    if (!roundId) throw new Error(mapSaveLineupErrorMessage(new Error("round_not_found")));

    try {
      return await saveLineupRpc(context.supabase, roundId, data);
    } catch (error) {
      throw new Error(mapSaveLineupErrorMessage(error));
    }
  });

type RosterRow = {
  id: string;
  is_reserved: boolean;
  players: {
    name: string;
    position: PlayerPosition;
    overall: number;
    velocity: number;
    finishing: number;
    passing: number;
    dribbling: number;
    defending: number;
    physical: number;
    goalkeeping: number;
  } | null;
  club_player_attribute_progress: Array<{
    attribute: string;
    progress: number;
    updated_at: string;
  }> | null;
};

async function loadSavedLineup(
  supabase: SupabaseClient<Database>,
  clubId: string,
  roundId: string,
): Promise<SavedLineupSnapshot | null> {
  const { data: lineup, error: lineupError } = await supabase
    .from("lineups")
    .select("id, formation, play_style, is_auto_generated")
    .eq("club_id", clubId)
    .eq("round_id", roundId)
    .maybeSingle();

  if (lineupError) throw new Error(lineupError.message);
  if (!lineup) return null;

  const { data: players, error: playersError } = await supabase
    .from("lineup_players")
    .select("club_player_id, slot_position, slot_index, is_starter")
    .eq("lineup_id", lineup.id)
    .order("is_starter", { ascending: false })
    .order("slot_position", { ascending: true })
    .order("slot_index", { ascending: true });

  if (playersError) throw new Error(playersError.message);

  return {
    formation: lineup.formation,
    style: lineup.play_style,
    isAutoGenerated: lineup.is_auto_generated,
    players: (players ?? []).map((player) => ({
      clubPlayerId: player.club_player_id,
      slotPosition: player.slot_position,
      slotIndex: player.slot_index,
      isStarter: player.is_starter,
    })),
  };
}

function toRosterPlayer(row: RosterRow): LineupRosterPlayer {
  const player = row.players;
  if (!player) {
    throw new Error("Jogador do elenco nao encontrado.");
  }
  const rosterPlayer: LineupRosterPlayer = {
    clubPlayerId: row.id,
    name: player.name,
    position: player.position,
    overall: player.overall,
    attributes: {
      velocity: player.velocity,
      finishing: player.finishing,
      passing: player.passing,
      dribbling: player.dribbling,
      defending: player.defending,
      physical: player.physical,
      goalkeeping: player.goalkeeping,
    },
    isReserved: row.is_reserved,
    attributeProgress: toAttributeProgress(row.club_player_attribute_progress ?? []),
  };
  return rosterPlayer;
}

function toAttributeProgress(
  rows: Array<{ attribute: string; progress: number; updated_at: string }>,
): LineupRosterPlayer["attributeProgress"] {
  return rows.flatMap((progress) =>
    isPlayerAttributeKey(progress.attribute)
      ? [
          {
            attribute: progress.attribute,
            progress: progress.progress,
            updatedAt: progress.updated_at,
          },
        ]
      : [],
  );
}

function isPlayerAttributeKey(value: string): value is (typeof PLAYER_ATTRIBUTE_KEYS)[number] {
  return PLAYER_ATTRIBUTE_KEYS.some((key) => key === value);
}
