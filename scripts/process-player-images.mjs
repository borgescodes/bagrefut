/**
 * Converte fotos brutas em public/players/<players.code>.webp.
 *
 * Uso completo:
 *   bun run assets:players -- --source <dir>
 *
 * Uso incremental por posição:
 *   bun run assets:players -- --source <dir> --position MID
 */

import { existsSync } from "node:fs";
import { mkdir, readdir } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import sharp from "sharp";
import { CROP_OVERRIDES, OUTPUT_SIZE, WEBP_QUALITY } from "./player-image-config.mjs";
import { createProcessingPlan, parseCliArgs } from "./player-image-input.mjs";

async function listFilesRecursively(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const nestedFiles = await Promise.all(
    entries.map((entry) => {
      const fullPath = path.join(directory, entry.name);
      return entry.isDirectory() ? listFilesRecursively(fullPath) : [fullPath];
    }),
  );
  return nestedFiles.flat();
}

async function main() {
  const args = parseCliArgs(process.argv.slice(2));
  const sourceDir = args.source
    ? path.resolve(args.source)
    : path.join(process.cwd(), "player-images-raw");
  const outputDir = path.join(process.cwd(), "public", "players");

  if (!existsSync(sourceDir)) {
    throw new Error(
      `Pasta de origem não encontrada: ${sourceDir}\n` +
        "Extraia as fotos brutas para ./player-images-raw ou informe --source <dir>.",
    );
  }

  const filePaths = await listFilesRecursively(sourceDir);
  const plan = createProcessingPlan(filePaths, args.position);
  await mkdir(outputDir, { recursive: true });

  if (plan.ignored.length > 0) {
    console.warn(
      `Ignorados (sem código válido): ${plan.ignored.map((file) => path.basename(file)).join(", ")}`,
    );
  }

  for (const code of plan.codes) {
    const inputPath = plan.filesByCode.get(code);
    const outputPath = path.join(outputDir, `${code}.webp`);
    const position = CROP_OVERRIDES[code] ?? sharp.strategy.attention;

    await sharp(inputPath)
      .rotate()
      .resize(OUTPUT_SIZE, OUTPUT_SIZE, { fit: "cover", position })
      .toColorspace("srgb")
      .webp({ quality: WEBP_QUALITY })
      .toFile(outputPath);

    console.log(`ok ${code}.webp`);
  }

  console.log(`\n${plan.codes.length} assets processados em public/players/.`);
}

main().catch((error) => {
  console.error(error.message ?? error);
  process.exitCode = 1;
});
