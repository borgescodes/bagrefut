import { describe, expect, it } from "vitest";
import {
  displaySector,
  normalizePlayerCode,
  playerCardFromDatabase,
  playerCardStats,
  playerImagePath,
  playerInitials,
} from "@/components/player-card";
import type { PlayerCardData } from "@/components/player-card";

/** Linha real do CSV players-export (GK01). */
const GK01_ID = "c35816ce-8471-4ec9-bce7-1eb34cd8e4d6";

const gk01Row = {
  id: GK01_ID,
  code: "GK01",
  name: "MARTINEZZ",
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
  name: "GORDAO DA XJ6",
  position: "ATA" as const,
  rarity: "pika" as const,
  sector: "cidade_nova",
};

describe("playerImagePath", () => {
  it("monta caminho com players.code em /players/<CODE>.webp", () => {
    expect(playerImagePath("ATA12")).toBe("/players/ATA12.webp");
  });

  it("normaliza trim e caixa baixa para o código canônico", () => {
    expect(playerImagePath("ata12")).toBe("/players/ATA12.webp");
    expect(playerImagePath("  def07 ")).toBe("/players/DEF07.webp");
  });

  it("nunca monta caminho com UUID", () => {
    expect(() => playerImagePath(GK01_ID)).toThrow();
  });

  it("rejeita códigos malformados ou fora da faixa", () => {
    expect(() => playerImagePath("ATA1")).toThrow();
    expect(() => playerImagePath("ATA99")).toThrow();
    expect(() => playerImagePath("XYZ01")).toThrow();
    expect(() => playerImagePath("")).toThrow();
    expect(() => playerImagePath("../etc/passwd")).toThrow();
  });

  it("resolve o asset da carta pelo code, nunca pelo id", () => {
    const card = playerCardFromDatabase(gk01Row);
    expect(playerImagePath(card.code)).toBe("/players/GK01.webp");
    expect(() => playerImagePath(card.id)).toThrow();
  });
});

describe("normalizePlayerCode", () => {
  it("aceita as faixas oficiais", () => {
    expect(normalizePlayerCode("GK12")).toBe("GK12");
    expect(normalizePlayerCode("DEF18")).toBe("DEF18");
    expect(normalizePlayerCode("MID18")).toBe("MID18");
    expect(normalizePlayerCode("ATA12")).toBe("ATA12");
  });

  it("rejeita fora da faixa por posição", () => {
    expect(() => normalizePlayerCode("GK13")).toThrow();
    expect(() => normalizePlayerCode("DEF19")).toThrow();
    expect(() => normalizePlayerCode("ATA13")).toThrow();
    expect(() => normalizePlayerCode("GK00")).toThrow();
  });
});

describe("playerInitials", () => {
  it("deriva iniciais do nome de display, nunca do code", () => {
    expect(playerInitials("PATOLINO CAVA UMA FALTA")).toBe("PF");
    expect(playerInitials("VOZINHA")).toBe("VO");
    expect(playerInitials("ZÉ FELIPE")).toBe("ZF");
  });
});

describe("displaySector", () => {
  it("usa os nomes canônicos de setor", () => {
    expect(displaySector("bela_vista")).toBe("bela vista");
    expect(displaySector("jaderlandia")).toBe("jardela");
    expect(displaySector("promessa")).toBe("promissão");
  });

  it("delega o fallback seguro sem uppercase", () => {
    expect(displaySector("  setor_novo ")).toBe("setor novo");
    expect(displaySector("paulo-sexto")).toBe("paulo sexo");
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
  it("mapeia linha do banco preservando players.name como display", () => {
    const card: PlayerCardData = playerCardFromDatabase(gk01Row);
    expect(card.id).toBe(GK01_ID);
    expect(card.code).toBe("GK01");
    expect(card.name).toBe("MARTINEZZ");
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

  it("rejeita code que é UUID", () => {
    expect(() => playerCardFromDatabase({ ...gk01Row, code: GK01_ID })).toThrow();
  });

  it("rejeita nome vazio", () => {
    expect(() => playerCardFromDatabase({ ...gk01Row, name: "   " })).toThrow();
  });
});
