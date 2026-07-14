import { readFileSync, readdirSync, statSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

/**
 * Guarda o contrato de assets de jogador:
 *   - asset = public/players/<players.code>.webp;
 *   - UUID nunca vira caminho de asset;
 *   - players.code nunca é renderizado na UI;
 *   - nenhum código é fabricado a partir de UUID.
 */

const SRC_DIR = path.join(process.cwd(), "src");
const MIGRATION_PATH = path.join(
  process.cwd(),
  "supabase",
  "migrations",
  "20260713120000_player_display_names.sql",
);

function listSourceFiles(dir: string): string[] {
  return readdirSync(dir).flatMap((entry) => {
    const fullPath = path.join(dir, entry);
    if (statSync(fullPath).isDirectory()) return listSourceFiles(fullPath);
    if (/\.(ts|tsx)$/.test(entry) && !entry.endsWith(".gen.ts")) return [fullPath];
    return [];
  });
}

const sourceFiles = listSourceFiles(SRC_DIR).filter(
  (file) => !file.endsWith("player-asset-contract.test.ts"),
);

function findMatches(pattern: RegExp): string[] {
  return sourceFiles.filter((file) => pattern.test(readFileSync(file, "utf8")));
}

describe("mapeamento de nomes (migration)", () => {
  const sql = readFileSync(MIGRATION_PATH, "utf8");

  it("contém exatamente 42 códigos ATA/DEF/GK", () => {
    const codes = [...sql.matchAll(/\('((?:ATA|DEF|GK)\d{2})',/g)].map((match) => match[1]);
    expect(codes).toHaveLength(42);
    expect(new Set(codes).size).toBe(42);
  });

  it("não altera jogadores MID", () => {
    expect(sql).not.toMatch(/\('MID\d{2}'/);
  });

  it("mantém o nome duplicado intencional VOZINHA em ATA11 e GK09", () => {
    expect(sql).toContain("('ATA11', 'VOZINHA')");
    expect(sql).toContain("('GK09', 'VOZINHA')");
  });
});

describe("padrões proibidos no código-fonte", () => {
  it("nenhum asset de jogador referenciado por UUID", () => {
    const uuidAsset = /\/players\/[0-9a-f]{8}-[0-9a-f]{4}-[^"'`]*\.webp/i;
    expect(findMatches(uuidAsset)).toEqual([]);
  });

  it("playerImagePath nunca recebe player.id ou playerId", () => {
    const idIntoPath = /playerImagePath\(\s*(?:\w+\.)*(?:player\.id|playerId)\b/;
    expect(findMatches(idIntoPath)).toEqual([]);
  });

  it("nenhum código fabricado com posição + trecho de UUID", () => {
    const fabricatedCode = /\$\{\s*\w+\.position\s*\}-\$\{\s*\w+\.(?:playerId|id)\.slice\(/;
    expect(findMatches(fabricatedCode)).toEqual([]);
  });

  it("player.code nunca é renderizado como texto JSX", () => {
    const renderedCode = />\s*\{\s*(?:\w+\.)?player\.code\s*\}\s*</;
    expect(findMatches(renderedCode)).toEqual([]);
  });

  it("aria-label nunca expõe player.code", () => {
    const ariaCode = /aria-label=\{[^}]*player\.code/;
    expect(findMatches(ariaCode)).toEqual([]);
  });
});
