import { describe, expect, it } from "vitest";
import {
  buildSaveLineupRpcArgs,
  mapSaveLineupErrorMessage,
  saveLineupRpc,
  type SaveLineupRpcClient,
} from "@/lib/lineup.functions";

const players = [
  {
    clubPlayerId: "00000000-0000-0000-0000-000000000001",
    slotPosition: "GK",
    slotIndex: 1,
    isStarter: true,
  },
  {
    clubPlayerId: "00000000-0000-0000-0000-000000000002",
    slotPosition: "DEF",
    slotIndex: 1,
    isStarter: true,
  },
  {
    clubPlayerId: "00000000-0000-0000-0000-000000000003",
    slotPosition: "DEF",
    slotIndex: 2,
    isStarter: true,
  },
  {
    clubPlayerId: "00000000-0000-0000-0000-000000000004",
    slotPosition: "MID",
    slotIndex: 1,
    isStarter: true,
  },
  {
    clubPlayerId: "00000000-0000-0000-0000-000000000005",
    slotPosition: "ATA",
    slotIndex: 1,
    isStarter: true,
  },
] as const;

describe("saveLineup RPC wrapper", () => {
  it("builds the exact RPC payload expected by the backend", () => {
    expect(
      buildSaveLineupRpcArgs("00000000-0000-0000-0000-000000000099", {
        formation: "1-2-1-1",
        style: "offensive",
        players,
      }),
    ).toEqual({
      _round_id: "00000000-0000-0000-0000-000000000099",
      _formation: "1-2-1-1",
      _play_style: "offensive",
      _players: [
        {
          club_player_id: "00000000-0000-0000-0000-000000000001",
          slot_position: "GK",
          slot_index: 1,
          is_starter: true,
        },
        {
          club_player_id: "00000000-0000-0000-0000-000000000002",
          slot_position: "DEF",
          slot_index: 1,
          is_starter: true,
        },
        {
          club_player_id: "00000000-0000-0000-0000-000000000003",
          slot_position: "DEF",
          slot_index: 2,
          is_starter: true,
        },
        {
          club_player_id: "00000000-0000-0000-0000-000000000004",
          slot_position: "MID",
          slot_index: 1,
          is_starter: true,
        },
        {
          club_player_id: "00000000-0000-0000-0000-000000000005",
          slot_position: "ATA",
          slot_index: 1,
          is_starter: true,
        },
      ],
    });
  });

  it("sends the save_lineup RPC and validates the response row", async () => {
    const calls: Array<ReturnType<typeof buildSaveLineupRpcArgs>> = [];
    const client: SaveLineupRpcClient = {
      async rpc(_name, args) {
        calls.push(args);
        return {
          data: [
            {
              lineup_id: "00000000-0000-0000-0000-000000000111",
              club_id: "00000000-0000-0000-0000-000000000222",
              round_id: args._round_id,
              formation: args._formation,
              play_style: args._play_style,
              player_count: 5,
              starter_count: 5,
              saved_at: "2026-07-09T21:00:00.000Z",
            },
          ],
          error: null,
        };
      },
    };

    const result = await saveLineupRpc(client, "00000000-0000-0000-0000-000000000099", {
      formation: "1-2-1-1",
      style: "offensive",
      players,
    });

    expect(calls).toHaveLength(1);
    expect(result.lineupId).toBe("00000000-0000-0000-0000-000000000111");
  });

  it("maps technical RPC errors to useful UI copy", async () => {
    const client: SaveLineupRpcClient = {
      async rpc() {
        return { data: null, error: { message: "lineup_locked" } };
      },
    };

    await expect(
      saveLineupRpc(client, "00000000-0000-0000-0000-000000000099", {
        formation: "1-2-1-1",
        style: "balanced",
        players,
      }),
    ).rejects.toThrow("O prazo para editar a escalação desta rodada já encerrou.");
  });

  it("keeps a direct mapper for UI error states", () => {
    expect(mapSaveLineupErrorMessage(new Error("duplicate_club_player"))).toBe(
      "O mesmo jogador não pode aparecer duas vezes.",
    );
  });
});
