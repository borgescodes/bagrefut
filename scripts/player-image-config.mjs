/**
 * Contrato dos assets de jogador.
 *
 * public/players/<players.code>.webp — o code (ex.: ATA12) é a chave técnica
 * do asset. UUID nunca é usado como nome de arquivo.
 */

export const PLAYER_CODE_RANGES = {
  GK: 12,
  DEF: 18,
  MID: 18,
  ATA: 12,
};

/** Códigos com asset de foto para o catálogo completo de 60 jogadores. */
export const EXPECTED_ASSET_CODES = ["GK", "DEF", "MID", "ATA"].flatMap((position) =>
  Array.from(
    { length: PLAYER_CODE_RANGES[position] },
    (_, index) => `${position}${String(index + 1).padStart(2, "0")}`,
  ),
);

export const OUTPUT_SIZE = 1024;
export const WEBP_QUALITY = 82;

/**
 * Overrides de crop por código, aplicados quando o crop automático por
 * atenção corta rosto/sujeito. Valores aceitos pelo sharp em `position`
 * (ex.: "top", "centre", "attention", "entropy").
 */
export const CROP_OVERRIDES = {
  // Rosto encostado na borda direita do original; attention cortava o rosto.
  DEF07: "right",
};
