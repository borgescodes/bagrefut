import { describe, expect, it } from "vitest";
import {
  displaySector,
  playerCardFromDatabase,
  playerCardStats,
  playerImagePath,
} from "@/components/player-card";
import type { PlayerCardData } from "@/components/player-card";

/** Linha real do CSV players-export (GK01). */
const GK01_ID = "c35816ce-8471-4ec9-bce7-1eb34cd8e4d6";

const gk01Row = {
  id: GK01_ID,
  code: "GK01",
  name: "GK01",
  position: "GK" as const,
  rarity: "peba" as const,
  sector: "bela_vista",
  overall: 46,
  velocity: 28,
  finishing: 6,
  passing: 32,
  dribbling: 11,
  defending: 33,
  physical: 36,
  goalkeeping: 56,
};

const outfieldRow = {
  ...gk01Row,
  id: "7b6e9a3c-1d2f-4e5a-8b9c-0d1e2f3a4b5c",
  code: "ATA07",
  name: "ATA07",
  position: "ATA" as const,
  rarity: "pika" as const,
  sector: "cidade_nova",
};

describe("playerImagePath", () => {
  it("monta caminho com players.id (UUID) em /players/<uuid>.webp", () => {
    expect(playerImagePath(GK01_ID)).toBe(`/players/${GK01_ID}.webp`);
  });

  it("GK01 resolve para o UUID do CSV, nunca GK01.webp", () => {
    const card = playerCardFromDatabase(gk01Row);
    const path = playerImagePath(card.id);
    expect(path).toBe(`/players/${GK01_ID}.webp`);
    expect(path).not.toContain("GK01.webp");
  });

  it("rejeita valores que não são UUID", () => {
    expect(() => playerImagePath("GK01")).toThrow();
    expect(() => playerImagePath("")).toThrow();
    expect(() => playerImagePath("../etc/passwd")).toThrow();
  });
});

describe("displaySector", () => {
  it("normaliza snake_case para display", () => {
    expect(displaySector("bela_vista")).toBe("BELA VISTA");
    expect(displaySector("cidade_nova")).toBe("CIDADE NOVA");
  });

  it("aguenta espaços e hífens extras", () => {
    expect(displaySector("  morada_do_sol ")).toBe("MORADA DO SOL");
    expect(displaySector("paulo-sexto")).toBe("PAULO SEXTO");
  });
});

describe("playerCardStats", () => {
  it("GK usa GK/DRI/VEL/DEF/PAS/PHY com goalkeeping no primeiro slot", () => {
    const card = playerCardFromDatabase(gk01Row);
    const stats = playerCardStats(card);
    expect(stats.map((s) => s.label)).toEqual(["GK", "DRI", "VEL", "DEF", "PAS", "PHY"]);
    expect(stats[0].value).toBe(56);
  });

  it("linha (DEF/MID/ATA) usa FIN/DRI/VEL/DEF/PAS/PHY", () => {
    const card = playerCardFromDatabase(outfieldRow);
    const stats = playerCardStats(card);
    expect(stats.map((s) => s.label)).toEqual(["FIN", "DRI", "VEL", "DEF", "PAS", "PHY"]);
    expect(stats[0].value).toBe(card.finishing);
  });
});

describe("playerCardFromDatabase", () => {
  it("mapeia linha do banco para o modelo visual usando players.name", () => {
    const card: PlayerCardData = playerCardFromDatabase(gk01Row);
    expect(card.id).toBe(GK01_ID);
    expect(card.code).toBe("GK01");
    expect(card.name).toBe("GK01");
    expect(card.rarity).toBe("peba");
    expect(card.overall).toBe(46);
  });

  it("clampa atributos fora da faixa 0..99", () => {
    const card = playerCardFromDatabase({ ...gk01Row, velocity: 240, passing: -5 });
    expect(card.velocity).toBe(99);
    expect(card.passing).toBe(0);
  });

  it("trata atributo não finito como 0", () => {
    const card = playerCardFromDatabase({ ...gk01Row, dribbling: Number.NaN });
    expect(card.dribbling).toBe(0);
  });

  it("rejeita raridade inválida", () => {
    expect(() => playerCardFromDatabase({ ...gk01Row, rarity: "lendaria" as never })).toThrow();
  });

  it("rejeita posição inválida", () => {
    expect(() => playerCardFromDatabase({ ...gk01Row, position: "ZAG" as never })).toThrow();
  });

  it("rejeita id que não é UUID", () => {
    expect(() => playerCardFromDatabase({ ...gk01Row, id: "GK01" })).toThrow();
  });

  it("rejeita nome vazio", () => {
    expect(() => playerCardFromDatabase({ ...gk01Row, name: "   " })).toThrow();
  });
});
