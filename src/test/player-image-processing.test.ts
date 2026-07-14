import path from "node:path";
import { pathToFileURL } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";

type ProcessingPlan = {
  codes: string[];
  filesByCode: Map<string, string>;
};

type PlayerImageInputModule = {
  createProcessingPlan: (filePaths: string[], position?: string) => ProcessingPlan;
};

const midFiles = Array.from(
  { length: 18 },
  (_, index) => `img mid/MID${String(index + 1).padStart(2, "0")}.webp`,
);

describe("processamento incremental de imagens", () => {
  let createProcessingPlan: PlayerImageInputModule["createProcessingPlan"];

  beforeAll(async () => {
    const moduleUrl = pathToFileURL(
      path.join(process.cwd(), "scripts", "player-image-input.mjs"),
    ).href;
    const imageInput = (await import(/* @vite-ignore */ moduleUrl)) as PlayerImageInputModule;
    createProcessingPlan = imageInput.createProcessingPlan;
  });

  it("--position MID seleciona exatamente MID01-MID18", () => {
    const plan = createProcessingPlan(midFiles, "MID");
    expect(plan.codes).toHaveLength(18);
    expect(plan.codes[0]).toBe("MID01");
    expect(plan.codes.at(-1)).toBe("MID18");
  });

  it("rejeita posição inválida", () => {
    expect(() => createProcessingPlan(midFiles, "LATERAL")).toThrow(/posição inválida/i);
  });

  it("rejeita código de outra posição no lote selecionado", () => {
    expect(() => createProcessingPlan([...midFiles, "ATA01.webp"], "MID")).toThrow(
      /fora da posição MID/i,
    );
  });

  it("rejeita código duplicado", () => {
    expect(() => createProcessingPlan([...midFiles, "MID01.png"], "MID")).toThrow(
      /MID01 duplicado/i,
    );
  });

  it("rejeita ausência de qualquer MID", () => {
    expect(() => createProcessingPlan(midFiles.slice(0, -1), "MID")).toThrow(
      /fotos ausentes.*MID18/i,
    );
  });

  it("não exige ATA, DEF ou GK ao processar somente MID", () => {
    expect(() => createProcessingPlan(midFiles, "MID")).not.toThrow();
  });
});
