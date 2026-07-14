import path from "node:path";
import { EXPECTED_ASSET_CODES, PLAYER_CODE_RANGES } from "./player-image-config.mjs";

const CODE_PATTERN = /^(GK|DEF|MID|ATA)\d{2}/i;
const VALID_POSITIONS = Object.freeze(Object.keys(PLAYER_CODE_RANGES));

function normalizePosition(position) {
  if (position === undefined) return undefined;
  const normalized = position.toUpperCase();
  if (!VALID_POSITIONS.includes(normalized)) {
    throw new Error(`Posição inválida: ${position}. Use ${VALID_POSITIONS.join("|")}.`);
  }
  return normalized;
}

export function expectedCodesForPosition(position) {
  const selectedPosition = normalizePosition(position);
  return selectedPosition
    ? EXPECTED_ASSET_CODES.filter((code) => code.startsWith(selectedPosition))
    : [...EXPECTED_ASSET_CODES];
}

export function createProcessingPlan(filePaths, position) {
  const selectedPosition = normalizePosition(position);
  const codes = expectedCodesForPosition(selectedPosition);
  const selectedCodes = new Set(codes);
  const filesByCode = new Map();
  const ignored = [];

  for (const filePath of [...filePaths].sort((left, right) => left.localeCompare(right))) {
    const fileName = path.basename(filePath);
    const match = CODE_PATTERN.exec(fileName);
    if (!match) {
      ignored.push(filePath);
      continue;
    }

    const code = match[0].toUpperCase();
    if (!EXPECTED_ASSET_CODES.includes(code)) {
      throw new Error(`Código ${code} (arquivo ${fileName}) não está na lista de assets.`);
    }
    if (!selectedCodes.has(code)) {
      throw new Error(
        `Código ${code} (arquivo ${fileName}) está fora da posição ${selectedPosition}.`,
      );
    }
    if (filesByCode.has(code)) {
      throw new Error(`Código ${code} duplicado: ${filesByCode.get(code)} e ${filePath}.`);
    }
    filesByCode.set(code, filePath);
  }

  const missing = codes.filter((code) => !filesByCode.has(code));
  if (missing.length > 0) {
    throw new Error(`Fotos ausentes para: ${missing.join(", ")}`);
  }

  return { codes, filesByCode, ignored };
}

export function parseCliArgs(args) {
  let source;
  let position;

  for (let index = 0; index < args.length; index += 1) {
    const argument = args[index];
    if (argument === "--source") {
      source = args[index + 1];
      if (!source) throw new Error("--source exige um diretório.");
      index += 1;
      continue;
    }
    if (argument === "--position") {
      position = args[index + 1];
      if (!position) throw new Error("--position exige GK|DEF|MID|ATA.");
      position = normalizePosition(position);
      index += 1;
      continue;
    }
    throw new Error(`Argumento desconhecido: ${argument}`);
  }

  return { source, position };
}
