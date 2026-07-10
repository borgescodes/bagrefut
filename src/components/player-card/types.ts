import type { PlayerPosition, PlayerRarity } from "@/domain/enums";

export type { PlayerPosition, PlayerRarity };

/**
 * Modelo visual da carta. Espelha o recorte de public.players necessário
 * para renderização; `name` vem direto de players.name (sem mapa paralelo).
 */
export type PlayerCardData = {
  id: string;
  code: string;
  name: string;
  position: PlayerPosition;
  rarity: PlayerRarity;
  sector: string;
  overall: number;
  velocity: number;
  finishing: number;
  passing: number;
  dribbling: number;
  defending: number;
  physical: number;
  goalkeeping: number;
};

/**
 * Recorte da linha de public.players aceito pelo adaptador.
 * Campos extras (reference_value_cents, created_at, ...) são ignorados.
 */
export type DatabasePlayerRecord = {
  id: string;
  code: string;
  name: string;
  position: PlayerPosition;
  rarity: PlayerRarity;
  sector: string;
  overall: number;
  velocity: number;
  finishing: number;
  passing: number;
  dribbling: number;
  defending: number;
  physical: number;
  goalkeeping: number;
};

export type PlayerCardProps = {
  player: PlayerCardData;
  className?: string;
  priority?: boolean;
  interactive?: boolean;
  selected?: boolean;
  disabled?: boolean;
};

export type PlayerCardStat = {
  label: string;
  value: number;
};
