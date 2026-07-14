import { readFileSync, readdirSync, statSync } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { describe, expect, it } from "vitest";

/**
 * Guarda o contrato de assets de jogador:
 *   - asset = public/players/<players.code>.webp;
 *   - UUID nunca vira caminho de asset;
 *   - players.code nunca é renderizado na UI;
 *   - nenhum código é fabricado a partir de UUID.
 */

const SRC_DIR = path.join(process.cwd(), "src");
const OLD_MIGRATION_PATH = path.join(
  process.cwd(),
  "supabase",
  "migrations",
  "20260713120000_player_display_names.sql",
);
const MID_MIGRATION_PATH = path.join(
  process.cwd(),
  "supabase",
  "migrations",
  "20260714120000_mid_player_display_names.sql",
);
const EXPECTED_MID_NAMES = new Map([
  ["MID01", "Gauvao"],
  ["MID02", "BELLIGOL"],
  ["MID03", "BAD 2"],
  ["MID04", "KIKO"],
  ["MID05", "ALOKque"],
  ["MID06", "sei la"],
  ["MID07", "DOLI"],
  ["MID08", "TCHOLA"],
  ["MID09", "MANEL GOMES"],
  ["MID10", "PAPAI KRISS"],
  ["MID11", "BAD LINDO"],
  ["MID12", "MIA KHALIFA"],
  ["MID13", "GORDOMIRO"],
  ["MID14", "AIII NOBRU"],
  ["MID15", "RUSBÉ"],
  ["MID16", "PESSE"],
  ["MID17", "NEIMAR JUNIO"],
  ["MID18", "GAYSTAVO"],
]);

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

function migrationPairs(sql: string, positions: string): [string, string][] {
  const pairPattern = new RegExp(`\\('((?:${positions})\\d{2})', '([^']+)'\\)`, "g");
  return [...sql.matchAll(pairPattern)].map((match) => [match[1], match[2]]);
}

describe("migration antiga de nomes ATA/DEF/GK", () => {
  const sql = readFileSync(OLD_MIGRATION_PATH, "utf8");

  it("contém exatamente 42 códigos ATA/DEF/GK", () => {
    const codes = migrationPairs(sql, "ATA|DEF|GK").map(([code]) => code);
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

describe("migration nova de nomes MID", () => {
  it("contém exatamente os 18 códigos MID únicos e o mapeamento oficial", () => {
    const sql = readFileSync(MID_MIGRATION_PATH, "utf8");
    const pairs = migrationPairs(sql, "MID");
    expect(pairs).toHaveLength(18);
    expect(new Set(pairs.map(([code]) => code)).size).toBe(18);
    expect(new Map(pairs)).toEqual(EXPECTED_MID_NAMES);
  });

  it("não altera ATA, DEF ou GK", () => {
    const sql = readFileSync(MID_MIGRATION_PATH, "utf8");
    expect(sql).not.toMatch(/\('(?:ATA|DEF|GK)\d{2}'/);
  });

  it("atualiza somente players.name", () => {
    const sql = readFileSync(MID_MIGRATION_PATH, "utf8");
    const updateBlock = sql.match(/UPDATE public\.players p[\s\S]*?GET DIAGNOSTICS/)?.[0];

    expect(updateBlock).toBeDefined();
    expect(updateBlock).toMatch(/SET name = btrim\(m\.display_name\)/);
    expect(updateBlock).not.toMatch(
      /\b(?:rarity|sector|overall|finishing|passing|dribbling|defending|velocity|physical|reference_value_cents|updated_at)\s*=/,
    );
  });
});

describe("contrato total de 60 assets", () => {
  it("EXPECTED_ASSET_CODES contém os 60 códigos oficiais, incluindo MID01-MID18", async () => {
    const moduleUrl = pathToFileURL(
      path.join(process.cwd(), "scripts", "player-image-config.mjs"),
    ).href;
    const config = (await import(/* @vite-ignore */ moduleUrl)) as Record<string, unknown>;
    const codes = config.EXPECTED_ASSET_CODES as string[];
    const expectedMid = Array.from(
      { length: 18 },
      (_, index) => `MID${String(index + 1).padStart(2, "0")}`,
    );

    expect(codes).toHaveLength(60);
    expect(new Set(codes).size).toBe(60);
    expect(codes).toEqual(expect.arrayContaining(expectedMid));
  });

  it("public/players contém exatamente 60 WebP oficiais", async () => {
    const moduleUrl = pathToFileURL(
      path.join(process.cwd(), "scripts", "player-image-config.mjs"),
    ).href;
    const config = (await import(/* @vite-ignore */ moduleUrl)) as Record<string, unknown>;
    const expectedFiles = (config.EXPECTED_ASSET_CODES as string[])
      .map((code) => `${code}.webp`)
      .sort();
    const actualFiles = readdirSync(path.join(process.cwd(), "public", "players"))
      .filter((file) => file.endsWith(".webp"))
      .sort();

    expect(actualFiles).toEqual(expectedFiles);
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
