/**
 * Valida os assets finais de jogador em public/players/.
 *
 * Garante o contrato public/players/<players.code>.webp:
 *   - exatamente os 60 assets esperados (GK01-12, DEF01-18, MID01-18, ATA01-12);
 *   - WebP real (magic bytes RIFF....WEBP), não só extensão;
 *   - dimensão 1024x1024;
 *   - nenhum JPEG/JPG/JFIF, nenhum UUID legado, nenhum arquivo inesperado.
 */

import { existsSync, readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { EXPECTED_ASSET_CODES, OUTPUT_SIZE } from "./player-image-config.mjs";

const PLAYERS_DIR = path.join(process.cwd(), "public", "players");
const ALLOWED_EXTRA_FILES = new Set(["README.md"]);
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\./i;
const FORBIDDEN_EXTENSIONS = /\.(jpe?g|jfif)$/i;

function fail(message) {
  throw new Error(`Player asset check failed: ${message}`);
}

/**
 * Lê dimensões de um WebP. Suporta VP8 (lossy), VP8L (lossless) e VP8X
 * (extended). Falha se o arquivo não for WebP real.
 */
function readWebpDimensions(filePath) {
  const buffer = readFileSync(filePath);
  const name = path.basename(filePath);
  if (
    buffer.length < 30 ||
    buffer.toString("ascii", 0, 4) !== "RIFF" ||
    buffer.toString("ascii", 8, 12) !== "WEBP"
  ) {
    fail(`${name} não é um arquivo WebP real`);
  }

  const chunk = buffer.toString("ascii", 12, 16);
  if (chunk === "VP8X") {
    return {
      width: 1 + buffer.readUIntLE(24, 3),
      height: 1 + buffer.readUIntLE(27, 3),
    };
  }
  if (chunk === "VP8L") {
    const bits = buffer.readUInt32LE(21);
    return {
      width: (bits & 0x3fff) + 1,
      height: ((bits >> 14) & 0x3fff) + 1,
    };
  }
  if (chunk === "VP8 ") {
    return {
      width: buffer.readUInt16LE(26) & 0x3fff,
      height: buffer.readUInt16LE(28) & 0x3fff,
    };
  }
  fail(`${name} tem chunk WebP desconhecido: ${chunk}`);
}

function main() {
  if (!existsSync(PLAYERS_DIR)) fail("public/players não existe");

  const files = readdirSync(PLAYERS_DIR);
  const assetFiles = files.filter((file) => !ALLOWED_EXTRA_FILES.has(file));

  if (assetFiles.length !== EXPECTED_ASSET_CODES.length) {
    fail(
      `esperava exatamente ${EXPECTED_ASSET_CODES.length} assets, encontrou ${assetFiles.length}`,
    );
  }

  for (const file of files) {
    if (ALLOWED_EXTRA_FILES.has(file)) continue;
    if (FORBIDDEN_EXTENSIONS.test(file)) fail(`extensão proibida em public/players: ${file}`);
    if (UUID_PATTERN.test(file)) fail(`asset UUID legado em public/players: ${file}`);
    if (/\s/.test(file)) fail(`nome de asset com espaço: ${file}`);
    if (/\.webp$/i.test(file) && path.parse(file).name !== path.parse(file).name.toUpperCase()) {
      fail(`código de asset deve estar em uppercase: ${file}`);
    }
    const expected = EXPECTED_ASSET_CODES.some((code) => file === `${code}.webp`);
    if (!expected) fail(`asset inesperado em public/players: ${file}`);
  }

  for (const code of EXPECTED_ASSET_CODES) {
    const filePath = path.join(PLAYERS_DIR, `${code}.webp`);
    if (!existsSync(filePath)) fail(`asset ausente: public/players/${code}.webp`);
    const { width, height } = readWebpDimensions(filePath);
    if (width !== OUTPUT_SIZE || height !== OUTPUT_SIZE) {
      fail(`${code}.webp deve ser ${OUTPUT_SIZE}x${OUTPUT_SIZE}, obtido ${width}x${height}`);
    }
  }

  console.log(`ok: ${EXPECTED_ASSET_CODES.length} assets válidos em public/players/.`);
}

main();
