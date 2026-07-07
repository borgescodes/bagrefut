/**
 * Enumerations mirroring Postgres enums declared in supabase/migrations.
 * Keep these string literal unions in sync with the database types.
 */

export type UserRole = "admin" | "user";
export type UserStatus = "pending" | "approved" | "blocked";
export type LeagueStatus = "setup" | "active" | "finished";

export type PlayerPosition = "GK" | "DEF" | "MID" | "ATA";
export type PlayerRarity = "peba" | "paia" | "pika";

export const PLAYER_SECTORS = [
  "centro",
  "cidade_nova",
  "promissao",
  "jaderlandia",
  "uraim",
  "jardim",
  "flamboyant",
  "angelim",
  "camboata",
  "buriti",
  "laercio",
  "bela_vista",
  "nagibao",
  "ipixuna",
  "caipe",
  "paulo_sexto",
  "morada_do_sol",
  "morada_do_vento",
  "nova_conquista",
] as const;
export type PlayerSector = (typeof PLAYER_SECTORS)[number];

export type PlayStyle = "balanced" | "offensive" | "defensive";
export type Formation = "1-2-1-1" | "1-1-2-1" | "1-1-1-2" | "0-2-2-1";
export const FORMATIONS: Formation[] = ["1-2-1-1", "1-1-2-1", "1-1-1-2", "0-2-2-1"];

export type MatchStatus = "scheduled" | "live" | "finished" | "cancelled";
export type MatchEventType =
  | "match_started"
  | "pressure"
  | "chance"
  | "shot"
  | "save"
  | "goal"
  | "halftime"
  | "match_finished";

export type MarketListingStatus = "open" | "sold" | "cancelled" | "expired";
export type TransferOfferStatus =
  | "pending"
  | "accepted"
  | "rejected"
  | "cancelled"
  | "expired";

export type WalletTransactionType =
  | "initial_credit"
  | "match_reward"
  | "season_prize"
  | "market_sale"
  | "market_purchase"
  | "system_sale"
  | "system_purchase"
  | "training_cost"
  | "transfer_cash"
  | "admin_adjustment";

export type NotificationType =
  | "account_approved"
  | "round_today"
  | "round_soon"
  | "round_result"
  | "offer_received"
  | "offer_accepted"
  | "offer_rejected"
  | "card_sold";

export type PlayerAttributeKey =
  | "velocity"
  | "finishing"
  | "passing"
  | "dribbling"
  | "defending"
  | "physical"
  | "goalkeeping";
