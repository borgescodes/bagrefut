/**
 * Converte as fotos brutas dos jogadores em assets finais WebP.
 *
 * Uso:
 *   node scripts/process-player-images.mjs [--source <dir>]
 *
 * A pasta de origem (padrão: ./player-images-raw, não versionada) contém as
 * fotos originais com nomes iniciados pelo código do jogador, por exemplo
 * "ATA12.jpeg.jpeg" ou "DEF11.jpg.jfif". O script:
 *
 *   1. extrai o código pelo padrão ^(GK|DEF|MID|ATA)\d{2};
 *   2. valida o código contra a lista oficial de assets esperados;
 *   3. aplica autorrotação EXIF, converte para sRGB e remove metadados;
 *   4. recorta em quadrado 1024x1024 (crop cover por atenção, com override
 *      manual por código em scripts/player-image-config.mjs);
 *   5. grava public/players/<CODE>.webp com qualidade 82.
 */

import { existsSync } from "node:fs";
import { mkdir, readdir } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import sharp from "sharp";
import {
  CROP_OVERRIDES,
  EXPECTED_ASSET_CODES,
  OUTPUT_SIZE,
  WEBP_QUALITY,
} from "./player-image-config.mjs";

const CODE_PATTERN = /^(GK|DEF|MID|ATA)\d{2}/i;

function resolveSourceDir() {
  const flagIndex = process.argv.indexOf("--source");
  if (flagIndex !== -1 && process.argv[flagIndex + 1]) {
    return path.resolve(process.argv[flagIndex + 1]);
  }
  return path.join(process.cwd(), "player-images-raw");
}

async function main() {
  const sourceDir = resolveSourceDir();
  const outputDir = path.join(process.cwd(), "public", "players");

  if (!existsSync(sourceDir)) {
    throw new Error(
      `Pasta de origem não encontrada: ${sourceDir}\n` +
        "Extraia as fotos brutas para ./player-images-raw ou informe --source <dir>.",
    );
  }

  await mkdir(outputDir, { recursive: true });

  const entries = (await readdir(sourceDir, { withFileTypes: true })).filter((entry) =>
    entry.isFile(),
  );

  const byCode = new Map();
  const ignored = [];
  for (const entry of entries) {
    const match = CODE_PATTERN.exec(entry.name);
    if (!match) {
      ignored.push(entry.name);
      continue;
    }
    const code = match[0].toUpperCase();
    if (!EXPECTED_ASSET_CODES.includes(code)) {
      throw new Error(`Código ${code} (arquivo ${entry.name}) não está na lista de assets.`);
    }
    if (byCode.has(code)) {
      throw new Error(`Código ${code} duplicado: ${byCode.get(code)} e ${entry.name}.`);
    }
    byCode.set(code, entry.name);
  }

  const missing = EXPECTED_ASSET_CODES.filter((code) => !byCode.has(code));
  if (missing.length > 0) {
    throw new Error(`Fotos ausentes para: ${missing.join(", ")}`);
  }
  if (ignored.length > 0) {
    console.warn(`Ignorados (sem código válido): ${ignored.join(", ")}`);
  }

  for (const code of EXPECTED_ASSET_CODES) {
    const inputPath = path.join(sourceDir, byCode.get(code));
    const outputPath = path.join(outputDir, `${code}.webp`);
    const position = CROP_OVERRIDES[code] ?? sharp.strategy.attention;

    await sharp(inputPath)
      .rotate() // autorrotação EXIF
      .resize(OUTPUT_SIZE, OUTPUT_SIZE, { fit: "cover", position })
      .toColorspace("srgb")
      .webp({ quality: WEBP_QUALITY })
      // toBuffer/toFile sem withMetadata() descarta EXIF/ICC de origem.
      .toFile(outputPath);

    console.log(`ok ${code}.webp`);
  }

  console.log(`\n${EXPECTED_ASSET_CODES.length} assets gerados em public/players/.`);
}

main().catch((error) => {
  console.error(error.message ?? error);
  process.exitCode = 1;
});
