import { describe, expect, it } from "vitest";
import {
  formatPlayerAttributeName,
  formatPlayStyleName,
  formatSectorName,
  SECTOR_DISPLAY_NAMES,
} from "@/lib/display-labels";

describe("formatSectorName", () => {
  it.each(Object.entries(SECTOR_DISPLAY_NAMES))("mapeia %s para %s", (value, label) => {
    expect(formatSectorName(value)).toBe(label);
  });

  it("normaliza separadores e espaços no fallback sem aplicar uppercase", () => {
    expect(formatSectorName("  setor__novo-comercial  ")).toBe("setor novo comercial");
    expect(formatSectorName("   ")).toBe("");
  });

  it("aceita entrada desconhecida sem lançar erro", () => {
    expect(() => formatSectorName("zona-rural")).not.toThrow();
    expect(formatSectorName("zona-rural")).toBe("zona rural");
  });
});

describe("labels de jogo", () => {
  it("traduz atributos persistidos sem alterar o valor original", () => {
    expect(formatPlayerAttributeName("velocity")).toBe("Velocidade");
    expect(formatPlayerAttributeName("goalkeeping")).toBe("Goleiro");
  });

  it("traduz estilos persistidos", () => {
    expect(formatPlayStyleName("balanced")).toBe("Equilibrado");
    expect(formatPlayStyleName("offensive")).toBe("Ofensivo");
    expect(formatPlayStyleName("defensive")).toBe("Defensivo");
  });
});
