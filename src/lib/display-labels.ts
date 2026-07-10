export const SECTOR_DISPLAY_NAMES: Record<string, string> = {
  bela_vista: "bela vista",
  jaderlandia: "jardela",
  caipe: "caipe",
  flamboyant: "flamboyant",
  morada_do_vento: "m. do vento",
  buriti: "buriti",
  cidade_nova: "cidade nova",
  nagibao: "nagibão",
  uraim: "uraim",
  paulo_sexto: "paulo sexo",
  angelim: "angelim",
  nova_conquista: "n. conquista",
  laercio: "laercio",
  promessa: "promissão",
  ipixuna: "ipixuna",
  jardim: "jardim",
  morada_do_sol: "m. do sol",
  camboata: "camboatã",
};

const SECTOR_DISPLAY_ALIASES: Record<string, string> = {
  promissao: "promissão",
};

export function formatSectorName(value: string): string {
  const normalized = value.trim().replace(/[_-]+/g, " ").replace(/\s+/g, " ");
  const key = normalized.replace(/\s+/g, "_");
  return SECTOR_DISPLAY_NAMES[key] ?? SECTOR_DISPLAY_ALIASES[key] ?? normalized;
}

const PLAYER_ATTRIBUTE_DISPLAY_NAMES: Record<string, string> = {
  velocity: "Velocidade",
  finishing: "Finalização",
  passing: "Passe",
  dribbling: "Drible",
  defending: "Defesa",
  physical: "Físico",
  goalkeeping: "Goleiro",
};

const PLAY_STYLE_DISPLAY_NAMES: Record<string, string> = {
  balanced: "Equilibrado",
  offensive: "Ofensivo",
  defensive: "Defensivo",
};

export function formatPlayerAttributeName(value: string): string {
  return PLAYER_ATTRIBUTE_DISPLAY_NAMES[value] ?? formatFallbackLabel(value);
}

export function formatPlayStyleName(value: string): string {
  return PLAY_STYLE_DISPLAY_NAMES[value] ?? formatFallbackLabel(value);
}

function formatFallbackLabel(value: string): string {
  const normalized = value.trim().replace(/[_-]+/g, " ").replace(/\s+/g, " ");
  return normalized.replace(/^./, (character) => character.toLocaleUpperCase("pt-BR"));
}
