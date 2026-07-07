import type {
  Formation,
  LeagueStatus,
  MarketListingStatus,
  MatchEventType,
  MatchStatus,
  NotificationType,
  PlayStyle,
  PlayerAttributeKey,
  PlayerPosition,
  PlayerRarity,
  PlayerSector,
  TransferOfferStatus,
  UserRole,
  UserStatus,
  WalletTransactionType,
} from "./enums";

export interface Profile {
  id: string;
  username: string;
  status: UserStatus;
  created_at: string;
  updated_at: string;
}

export interface UserRoleRow {
  id: string;
  user_id: string;
  role: UserRole;
  created_at: string;
}

export interface League {
  id: string;
  slug: string;
  name: string;
  max_clubs: number;
  status: LeagueStatus;
  created_at: string;
  updated_at: string;
}

export interface ClubBadge {
  id: string;
  code: string;
  label: string;
  asset_path: string;
  sort_order: number;
  is_active: boolean;
}

export interface Club {
  id: string;
  league_id: string;
  owner_id: string;
  name: string;
  abbreviation: string;
  badge_id: string;
  balance_cents: number;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

export type PlayerAttributes = Record<PlayerAttributeKey, number>;

export interface Player extends PlayerAttributes {
  id: string;
  code: string;
  name: string;
  position: PlayerPosition;
  rarity: PlayerRarity;
  sector: PlayerSector;
  overall: number;
  reference_value_cents: number;
  created_at: string;
  updated_at: string;
}

export interface ClubPlayer {
  id: string;
  club_id: string;
  player_id: string;
  acquired_at: string;
  is_reserved: boolean;
}

export interface InitialPack {
  id: string;
  club_id: string;
  opened_at: string | null;
  created_at: string;
}

export interface InitialPackItem {
  id: string;
  pack_id: string;
  player_id: string;
  slot: number;
}

export interface Season {
  id: string;
  league_id: string;
  season_number: number;
  status: "scheduled" | "active" | "finished";
  started_at: string | null;
  finished_at: string | null;
  seed: string; // bigint serialized
}

export interface Round {
  id: string;
  season_id: string;
  round_number: number;
  lineup_lock_at: string;
  starts_at: string;
  ends_at: string;
  is_processed: boolean;
}

export interface Match {
  id: string;
  round_id: string;
  home_club_id: string;
  away_club_id: string;
  home_goals: number;
  away_goals: number;
  status: MatchStatus;
  seed: string | null;
  simulated_at: string | null;
}

export interface MatchEvent {
  id: string;
  match_id: string;
  minute: number;
  reveal_at: string;
  event_type: MatchEventType;
  club_id: string | null;
  player_id: string | null;
  meta: Record<string, unknown>;
}

export interface Lineup {
  id: string;
  club_id: string;
  round_id: string;
  formation: Formation;
  play_style: PlayStyle;
  is_auto_generated: boolean;
}

export interface LineupPlayer {
  id: string;
  lineup_id: string;
  club_player_id: string;
  slot_position: PlayerPosition;
  is_starter: boolean;
  slot_index: number;
}

export interface TrainingSession {
  id: string;
  club_id: string;
  club_player_id: string;
  attribute: PlayerAttributeKey;
  cost_cents: number;
  day: string;
  progress_delta: number;
}

export interface MarketListing {
  id: string;
  seller_club_id: string;
  club_player_id: string;
  price_cents: number;
  status: MarketListingStatus;
  closed_at: string | null;
}

export interface TransferOffer {
  id: string;
  from_club_id: string;
  to_club_id: string;
  cash_cents: number;
  status: TransferOfferStatus;
  expires_at: string;
  resolved_at: string | null;
}

export interface TransferOfferItem {
  id: string;
  offer_id: string;
  club_player_id: string;
  side: "from" | "to";
}

export interface WalletTransaction {
  id: string;
  club_id: string;
  amount_cents: number;
  balance_after_cents: number;
  kind: WalletTransactionType;
  reference_table: string | null;
  reference_id: string | null;
  memo: string | null;
  created_at: string;
}

export interface PushSubscriptionRow {
  id: string;
  user_id: string;
  endpoint: string;
  p256dh: string;
  auth_key: string;
  user_agent: string | null;
}

export interface AdminAuditLog {
  id: string;
  admin_id: string;
  action: string;
  target_table: string | null;
  target_id: string | null;
  payload: Record<string, unknown>;
  created_at: string;
}

export type NotificationPayload = { type: NotificationType; [key: string]: unknown };
