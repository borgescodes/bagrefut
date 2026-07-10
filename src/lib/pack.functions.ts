import { createServerFn } from "@tanstack/react-start";
import type { SupabaseClient } from "@supabase/supabase-js";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import type { Database } from "@/integrations/supabase/types";
import { playerPositionSchema, playerRaritySchema } from "@/domain/market";
import { playerCardFromDatabase } from "@/components/player-card/adapter";
import type { PlayerCardData } from "@/components/player-card/types";

/**
 * Server functions do pacote inicial. Sempre via context.supabase (RLS).
 * Nenhum acesso service role, SQL manual ou CSV em runtime.
 */

const playerRowSchema = z.object({
  id: z.string().uuid(),
  code: z.string().min(1),
  name: z.string().min(1),
  position: playerPositionSchema,
  rarity: playerRaritySchema,
  sector: z.string().min(1),
  overall: z.number(),
  velocity: z.number(),
  finishing: z.number(),
  passing: z.number(),
  dribbling: z.number(),
  defending: z.number(),
  physical: z.number(),
  goalkeeping: z.number(),
});

const packItemRowSchema = z.object({
  slot: z.number().int().min(1),
  player_id: z.string().uuid(),
});

const PLAYER_CARD_COLUMNS =
  "id, code, name, position, rarity, sector, overall, velocity, finishing, passing, dribbling, defending, physical, goalkeeping";

export type PackCard = {
  slot: number;
  player: PlayerCardData;
};

export type InitialPackExperience = {
  pack: {
    id: string;
    clubId: string;
    openedAt: string | null;
  } | null;
  cards: PackCard[];
};

type AuthedContext = {
  supabase: SupabaseClient<Database>;
  userId: string;
};

async function loadInitialPackExperience(context: AuthedContext): Promise<InitialPackExperience> {
  const { supabase, userId } = context;

  const clubRes = await supabase.from("clubs").select("id").eq("owner_id", userId).maybeSingle();
  if (clubRes.error) throw new Error(clubRes.error.message);
  if (!clubRes.data) return { pack: null, cards: [] };

  const packRes = await supabase
    .from("initial_packs")
    .select("id, club_id, opened_at")
    .eq("club_id", clubRes.data.id)
    .maybeSingle();
  if (packRes.error) throw new Error(packRes.error.message);
  if (!packRes.data) return { pack: null, cards: [] };

  const pack = {
    id: packRes.data.id,
    clubId: packRes.data.club_id,
    openedAt: packRes.data.opened_at,
  };

  if (!pack.openedAt) return { pack, cards: [] };

  const itemsRes = await supabase
    .from("initial_pack_items")
    .select("slot, player_id")
    .eq("pack_id", pack.id)
    .order("slot", { ascending: true });
  if (itemsRes.error) throw new Error(itemsRes.error.message);

  const items = z.array(packItemRowSchema).parse(itemsRes.data ?? []);
  if (items.length === 0) return { pack, cards: [] };

  const playersRes = await supabase
    .from("players")
    .select(PLAYER_CARD_COLUMNS)
    .in(
      "id",
      items.map((item) => item.player_id),
    );
  if (playersRes.error) throw new Error(playersRes.error.message);

  const playersById = new Map<string, PlayerCardData>();
  for (const row of z.array(playerRowSchema).parse(playersRes.data ?? [])) {
    playersById.set(row.id, playerCardFromDatabase(row));
  }

  const cards = items.map((item) => {
    const player = playersById.get(item.player_id);
    if (!player) {
      throw new Error(`Jogador ${item.player_id} do pacote não encontrado em players.`);
    }
    return { slot: item.slot, player };
  });

  return { pack, cards };
}

/**
 * Estado atual da experiência do pacote inicial do usuário.
 * Pacote fechado retorna cards: []; aberto retorna as 10 cartas completas.
 */
export const getInitialPackExperience = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }): Promise<InitialPackExperience> => {
    return loadInitialPackExperience(context);
  });

/**
 * Abre o pacote inicial via RPC transacional open_initial_pack e recarrega
 * pacote + itens + jogadores do banco. Não confia no retorno mínimo da RPC.
 */
export const openInitialPack = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((data: unknown) => z.object({ clubId: z.string().uuid() }).parse(data))
  .handler(async ({ data, context }): Promise<InitialPackExperience> => {
    const { error } = await context.supabase.rpc("open_initial_pack", {
      _club_id: data.clubId,
    });
    if (error) throw new Error(error.message);

    const experience = await loadInitialPackExperience(context);
    if (!experience.pack || !experience.pack.openedAt) {
      throw new Error("Pacote não confirmado como aberto após a RPC.");
    }
    if (experience.cards.length === 0) {
      throw new Error("Pacote aberto sem cartas registradas.");
    }
    return experience;
  });
