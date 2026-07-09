export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      admin_audit_logs: {
        Row: {
          action: string
          admin_id: string
          created_at: string
          id: string
          payload: Json
          target_id: string | null
          target_table: string | null
        }
        Insert: {
          action: string
          admin_id: string
          created_at?: string
          id?: string
          payload?: Json
          target_id?: string | null
          target_table?: string | null
        }
        Update: {
          action?: string
          admin_id?: string
          created_at?: string
          id?: string
          payload?: Json
          target_id?: string | null
          target_table?: string | null
        }
        Relationships: []
      }
      club_badges: {
        Row: {
          asset_path: string
          code: string
          created_at: string
          id: string
          is_active: boolean
          label: string
          sort_order: number
        }
        Insert: {
          asset_path: string
          code: string
          created_at?: string
          id?: string
          is_active?: boolean
          label: string
          sort_order?: number
        }
        Update: {
          asset_path?: string
          code?: string
          created_at?: string
          id?: string
          is_active?: boolean
          label?: string
          sort_order?: number
        }
        Relationships: []
      }
      club_player_attribute_progress: {
        Row: {
          attribute: string
          club_player_id: string
          progress: number
          updated_at: string
        }
        Insert: {
          attribute: string
          club_player_id: string
          progress?: number
          updated_at?: string
        }
        Update: {
          attribute?: string
          club_player_id?: string
          progress?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "club_player_attribute_progress_club_player_id_fkey"
            columns: ["club_player_id"]
            isOneToOne: false
            referencedRelation: "club_players"
            referencedColumns: ["id"]
          },
        ]
      }
      club_players: {
        Row: {
          acquired_at: string
          club_id: string | null
          id: string
          is_reserved: boolean
          player_id: string
        }
        Insert: {
          acquired_at?: string
          club_id?: string | null
          id?: string
          is_reserved?: boolean
          player_id: string
        }
        Update: {
          acquired_at?: string
          club_id?: string | null
          id?: string
          is_reserved?: boolean
          player_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "club_players_club_id_fkey"
            columns: ["club_id"]
            isOneToOne: false
            referencedRelation: "clubs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "club_players_player_id_fkey"
            columns: ["player_id"]
            isOneToOne: true
            referencedRelation: "players"
            referencedColumns: ["id"]
          },
        ]
      }
      clubs: {
        Row: {
          abbreviation: string
          badge_id: string
          balance_cents: number
          created_at: string
          id: string
          is_active: boolean
          league_id: string
          name: string
          normalized_name: string
          owner_id: string
          updated_at: string
        }
        Insert: {
          abbreviation: string
          badge_id: string
          balance_cents?: number
          created_at?: string
          id?: string
          is_active?: boolean
          league_id: string
          name: string
          normalized_name: string
          owner_id: string
          updated_at?: string
        }
        Update: {
          abbreviation?: string
          badge_id?: string
          balance_cents?: number
          created_at?: string
          id?: string
          is_active?: boolean
          league_id?: string
          name?: string
          normalized_name?: string
          owner_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "clubs_badge_id_fkey"
            columns: ["badge_id"]
            isOneToOne: false
            referencedRelation: "club_badges"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clubs_league_id_fkey"
            columns: ["league_id"]
            isOneToOne: false
            referencedRelation: "leagues"
            referencedColumns: ["id"]
          },
        ]
      }
      initial_pack_items: {
        Row: {
          id: string
          pack_id: string
          player_id: string
          slot: number
        }
        Insert: {
          id?: string
          pack_id: string
          player_id: string
          slot: number
        }
        Update: {
          id?: string
          pack_id?: string
          player_id?: string
          slot?: number
        }
        Relationships: [
          {
            foreignKeyName: "initial_pack_items_pack_id_fkey"
            columns: ["pack_id"]
            isOneToOne: false
            referencedRelation: "initial_packs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "initial_pack_items_player_id_fkey"
            columns: ["player_id"]
            isOneToOne: false
            referencedRelation: "players"
            referencedColumns: ["id"]
          },
        ]
      }
      initial_packs: {
        Row: {
          club_id: string
          created_at: string
          id: string
          opened_at: string | null
        }
        Insert: {
          club_id: string
          created_at?: string
          id?: string
          opened_at?: string | null
        }
        Update: {
          club_id?: string
          created_at?: string
          id?: string
          opened_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "initial_packs_club_id_fkey"
            columns: ["club_id"]
            isOneToOne: true
            referencedRelation: "clubs"
            referencedColumns: ["id"]
          },
        ]
      }
      leagues: {
        Row: {
          created_at: string
          id: string
          max_clubs: number
          name: string
          slug: string
          status: Database["public"]["Enums"]["league_status"]
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          max_clubs?: number
          name: string
          slug: string
          status?: Database["public"]["Enums"]["league_status"]
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          max_clubs?: number
          name?: string
          slug?: string
          status?: Database["public"]["Enums"]["league_status"]
          updated_at?: string
        }
        Relationships: []
      }
      lineup_players: {
        Row: {
          club_player_id: string
          id: string
          is_starter: boolean
          lineup_id: string
          slot_index: number
          slot_position: Database["public"]["Enums"]["player_position"]
        }
        Insert: {
          club_player_id: string
          id?: string
          is_starter: boolean
          lineup_id: string
          slot_index: number
          slot_position: Database["public"]["Enums"]["player_position"]
        }
        Update: {
          club_player_id?: string
          id?: string
          is_starter?: boolean
          lineup_id?: string
          slot_index?: number
          slot_position?: Database["public"]["Enums"]["player_position"]
        }
        Relationships: [
          {
            foreignKeyName: "lineup_players_club_player_id_fkey"
            columns: ["club_player_id"]
            isOneToOne: false
            referencedRelation: "club_players"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lineup_players_lineup_id_fkey"
            columns: ["lineup_id"]
            isOneToOne: false
            referencedRelation: "lineups"
            referencedColumns: ["id"]
          },
        ]
      }
      lineups: {
        Row: {
          club_id: string
          created_at: string
          formation: Database["public"]["Enums"]["formation"]
          id: string
          is_auto_generated: boolean
          play_style: Database["public"]["Enums"]["play_style"]
          round_id: string
          updated_at: string
        }
        Insert: {
          club_id: string
          created_at?: string
          formation: Database["public"]["Enums"]["formation"]
          id?: string
          is_auto_generated?: boolean
          play_style?: Database["public"]["Enums"]["play_style"]
          round_id: string
          updated_at?: string
        }
        Update: {
          club_id?: string
          created_at?: string
          formation?: Database["public"]["Enums"]["formation"]
          id?: string
          is_auto_generated?: boolean
          play_style?: Database["public"]["Enums"]["play_style"]
          round_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "lineups_club_id_fkey"
            columns: ["club_id"]
            isOneToOne: false
            referencedRelation: "clubs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lineups_round_id_fkey"
            columns: ["round_id"]
            isOneToOne: false
            referencedRelation: "rounds"
            referencedColumns: ["id"]
          },
        ]
      }
      market_listings: {
        Row: {
          closed_at: string | null
          club_player_id: string
          created_at: string
          id: string
          price_cents: number
          seller_club_id: string
          status: Database["public"]["Enums"]["market_listing_status"]
          updated_at: string
        }
        Insert: {
          closed_at?: string | null
          club_player_id: string
          created_at?: string
          id?: string
          price_cents: number
          seller_club_id: string
          status?: Database["public"]["Enums"]["market_listing_status"]
          updated_at?: string
        }
        Update: {
          closed_at?: string | null
          club_player_id?: string
          created_at?: string
          id?: string
          price_cents?: number
          seller_club_id?: string
          status?: Database["public"]["Enums"]["market_listing_status"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "market_listings_club_player_id_fkey"
            columns: ["club_player_id"]
            isOneToOne: false
            referencedRelation: "club_players"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "market_listings_seller_club_id_fkey"
            columns: ["seller_club_id"]
            isOneToOne: false
            referencedRelation: "clubs"
            referencedColumns: ["id"]
          },
        ]
      }
      match_events: {
        Row: {
          club_id: string | null
          created_at: string
          event_type: Database["public"]["Enums"]["match_event_type"]
          id: string
          match_id: string
          meta: Json
          minute: number
          player_id: string | null
          reveal_at: string
        }
        Insert: {
          club_id?: string | null
          created_at?: string
          event_type: Database["public"]["Enums"]["match_event_type"]
          id?: string
          match_id: string
          meta?: Json
          minute: number
          player_id?: string | null
          reveal_at: string
        }
        Update: {
          club_id?: string | null
          created_at?: string
          event_type?: Database["public"]["Enums"]["match_event_type"]
          id?: string
          match_id?: string
          meta?: Json
          minute?: number
          player_id?: string | null
          reveal_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "match_events_club_id_fkey"
            columns: ["club_id"]
            isOneToOne: false
            referencedRelation: "clubs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "match_events_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "match_events_player_id_fkey"
            columns: ["player_id"]
            isOneToOne: false
            referencedRelation: "players"
            referencedColumns: ["id"]
          },
        ]
      }
      matches: {
        Row: {
          away_club_id: string
          away_goals: number
          created_at: string
          home_club_id: string
          home_goals: number
          id: string
          round_id: string
          seed: number | null
          simulated_at: string | null
          status: Database["public"]["Enums"]["match_status"]
          updated_at: string
        }
        Insert: {
          away_club_id: string
          away_goals?: number
          created_at?: string
          home_club_id: string
          home_goals?: number
          id?: string
          round_id: string
          seed?: number | null
          simulated_at?: string | null
          status?: Database["public"]["Enums"]["match_status"]
          updated_at?: string
        }
        Update: {
          away_club_id?: string
          away_goals?: number
          created_at?: string
          home_club_id?: string
          home_goals?: number
          id?: string
          round_id?: string
          seed?: number | null
          simulated_at?: string | null
          status?: Database["public"]["Enums"]["match_status"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "matches_away_club_id_fkey"
            columns: ["away_club_id"]
            isOneToOne: false
            referencedRelation: "clubs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "matches_home_club_id_fkey"
            columns: ["home_club_id"]
            isOneToOne: false
            referencedRelation: "clubs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "matches_round_id_fkey"
            columns: ["round_id"]
            isOneToOne: false
            referencedRelation: "rounds"
            referencedColumns: ["id"]
          },
        ]
      }
      players: {
        Row: {
          code: string
          created_at: string
          defending: number
          dribbling: number
          finishing: number
          goalkeeping: number
          id: string
          name: string
          overall: number
          passing: number
          physical: number
          position: Database["public"]["Enums"]["player_position"]
          rarity: Database["public"]["Enums"]["player_rarity"]
          reference_value_cents: number
          sector: Database["public"]["Enums"]["player_sector"]
          updated_at: string
          velocity: number
        }
        Insert: {
          code: string
          created_at?: string
          defending: number
          dribbling: number
          finishing: number
          goalkeeping: number
          id?: string
          name: string
          overall: number
          passing: number
          physical: number
          position: Database["public"]["Enums"]["player_position"]
          rarity: Database["public"]["Enums"]["player_rarity"]
          reference_value_cents: number
          sector: Database["public"]["Enums"]["player_sector"]
          updated_at?: string
          velocity: number
        }
        Update: {
          code?: string
          created_at?: string
          defending?: number
          dribbling?: number
          finishing?: number
          goalkeeping?: number
          id?: string
          name?: string
          overall?: number
          passing?: number
          physical?: number
          position?: Database["public"]["Enums"]["player_position"]
          rarity?: Database["public"]["Enums"]["player_rarity"]
          reference_value_cents?: number
          sector?: Database["public"]["Enums"]["player_sector"]
          updated_at?: string
          velocity?: number
        }
        Relationships: []
      }
      profiles: {
        Row: {
          created_at: string
          id: string
          status: Database["public"]["Enums"]["user_status"]
          updated_at: string
          username: string
        }
        Insert: {
          created_at?: string
          id: string
          status?: Database["public"]["Enums"]["user_status"]
          updated_at?: string
          username: string
        }
        Update: {
          created_at?: string
          id?: string
          status?: Database["public"]["Enums"]["user_status"]
          updated_at?: string
          username?: string
        }
        Relationships: []
      }
      push_subscriptions: {
        Row: {
          auth_key: string
          created_at: string
          endpoint: string
          id: string
          p256dh: string
          user_agent: string | null
          user_id: string
        }
        Insert: {
          auth_key: string
          created_at?: string
          endpoint: string
          id?: string
          p256dh: string
          user_agent?: string | null
          user_id: string
        }
        Update: {
          auth_key?: string
          created_at?: string
          endpoint?: string
          id?: string
          p256dh?: string
          user_agent?: string | null
          user_id?: string
        }
        Relationships: []
      }
      rounds: {
        Row: {
          ends_at: string
          id: string
          is_processed: boolean
          lineup_lock_at: string
          round_number: number
          season_id: string
          starts_at: string
        }
        Insert: {
          ends_at: string
          id?: string
          is_processed?: boolean
          lineup_lock_at: string
          round_number: number
          season_id: string
          starts_at: string
        }
        Update: {
          ends_at?: string
          id?: string
          is_processed?: boolean
          lineup_lock_at?: string
          round_number?: number
          season_id?: string
          starts_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "rounds_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: false
            referencedRelation: "seasons"
            referencedColumns: ["id"]
          },
        ]
      }
      seasons: {
        Row: {
          created_at: string
          finished_at: string | null
          id: string
          league_id: string
          season_number: number
          seed: number
          started_at: string | null
          status: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          finished_at?: string | null
          id?: string
          league_id: string
          season_number: number
          seed?: number
          started_at?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          finished_at?: string | null
          id?: string
          league_id?: string
          season_number?: number
          seed?: number
          started_at?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "seasons_league_id_fkey"
            columns: ["league_id"]
            isOneToOne: false
            referencedRelation: "leagues"
            referencedColumns: ["id"]
          },
        ]
      }
      system_market_stock: {
        Row: {
          acquired_at: string
          acquired_from_club_id: string | null
          acquired_price_cents: number
          club_player_id: string
        }
        Insert: {
          acquired_at?: string
          acquired_from_club_id?: string | null
          acquired_price_cents?: number
          club_player_id: string
        }
        Update: {
          acquired_at?: string
          acquired_from_club_id?: string | null
          acquired_price_cents?: number
          club_player_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "system_market_stock_acquired_from_club_id_fkey"
            columns: ["acquired_from_club_id"]
            isOneToOne: false
            referencedRelation: "clubs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "system_market_stock_club_player_id_fkey"
            columns: ["club_player_id"]
            isOneToOne: true
            referencedRelation: "club_players"
            referencedColumns: ["id"]
          },
        ]
      }
      training_sessions: {
        Row: {
          attribute: string
          attribute_after: number | null
          attribute_before: number | null
          club_id: string
          club_player_id: string
          cost_cents: number
          created_at: string
          day: string
          id: string
          overall_after: number | null
          overall_before: number | null
          progress_after: number | null
          progress_before: number | null
          progress_delta: number
          reference_value_after_cents: number | null
          reference_value_before_cents: number | null
        }
        Insert: {
          attribute: string
          attribute_after?: number | null
          attribute_before?: number | null
          club_id: string
          club_player_id: string
          cost_cents: number
          created_at?: string
          day?: string
          id?: string
          overall_after?: number | null
          overall_before?: number | null
          progress_after?: number | null
          progress_before?: number | null
          progress_delta?: number
          reference_value_after_cents?: number | null
          reference_value_before_cents?: number | null
        }
        Update: {
          attribute?: string
          attribute_after?: number | null
          attribute_before?: number | null
          club_id?: string
          club_player_id?: string
          cost_cents?: number
          created_at?: string
          day?: string
          id?: string
          overall_after?: number | null
          overall_before?: number | null
          progress_after?: number | null
          progress_before?: number | null
          progress_delta?: number
          reference_value_after_cents?: number | null
          reference_value_before_cents?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "training_sessions_club_id_fkey"
            columns: ["club_id"]
            isOneToOne: false
            referencedRelation: "clubs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "training_sessions_club_player_id_fkey"
            columns: ["club_player_id"]
            isOneToOne: false
            referencedRelation: "club_players"
            referencedColumns: ["id"]
          },
        ]
      }
      transfer_offer_items: {
        Row: {
          club_player_id: string
          id: string
          offer_id: string
          side: string
        }
        Insert: {
          club_player_id: string
          id?: string
          offer_id: string
          side: string
        }
        Update: {
          club_player_id?: string
          id?: string
          offer_id?: string
          side?: string
        }
        Relationships: [
          {
            foreignKeyName: "transfer_offer_items_club_player_id_fkey"
            columns: ["club_player_id"]
            isOneToOne: false
            referencedRelation: "club_players"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transfer_offer_items_offer_id_fkey"
            columns: ["offer_id"]
            isOneToOne: false
            referencedRelation: "transfer_offers"
            referencedColumns: ["id"]
          },
        ]
      }
      transfer_offers: {
        Row: {
          cash_cents: number
          created_at: string
          expires_at: string
          from_club_id: string
          id: string
          resolved_at: string | null
          status: Database["public"]["Enums"]["transfer_offer_status"]
          to_club_id: string
          updated_at: string
        }
        Insert: {
          cash_cents?: number
          created_at?: string
          expires_at?: string
          from_club_id: string
          id?: string
          resolved_at?: string | null
          status?: Database["public"]["Enums"]["transfer_offer_status"]
          to_club_id: string
          updated_at?: string
        }
        Update: {
          cash_cents?: number
          created_at?: string
          expires_at?: string
          from_club_id?: string
          id?: string
          resolved_at?: string | null
          status?: Database["public"]["Enums"]["transfer_offer_status"]
          to_club_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "transfer_offers_from_club_id_fkey"
            columns: ["from_club_id"]
            isOneToOne: false
            referencedRelation: "clubs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transfer_offers_to_club_id_fkey"
            columns: ["to_club_id"]
            isOneToOne: false
            referencedRelation: "clubs"
            referencedColumns: ["id"]
          },
        ]
      }
      user_roles: {
        Row: {
          created_at: string
          id: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          role?: Database["public"]["Enums"]["app_role"]
          user_id?: string
        }
        Relationships: []
      }
      wallet_transactions: {
        Row: {
          amount_cents: number
          balance_after_cents: number
          club_id: string
          created_at: string
          id: string
          kind: Database["public"]["Enums"]["wallet_transaction_type"]
          memo: string | null
          reference_id: string | null
          reference_table: string | null
        }
        Insert: {
          amount_cents: number
          balance_after_cents: number
          club_id: string
          created_at?: string
          id?: string
          kind: Database["public"]["Enums"]["wallet_transaction_type"]
          memo?: string | null
          reference_id?: string | null
          reference_table?: string | null
        }
        Update: {
          amount_cents?: number
          balance_after_cents?: number
          club_id?: string
          created_at?: string
          id?: string
          kind?: Database["public"]["Enums"]["wallet_transaction_type"]
          memo?: string | null
          reference_id?: string | null
          reference_table?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "wallet_transactions_club_id_fkey"
            columns: ["club_id"]
            isOneToOne: false
            referencedRelation: "clubs"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      _credit_wallet: {
        Args: {
          _amount_cents: number
          _club_id: string
          _kind: Database["public"]["Enums"]["wallet_transaction_type"]
          _memo: string
          _ref_id: string
          _ref_table: string
        }
        Returns: number
      }
      _debit_wallet: {
        Args: {
          _amount_cents: number
          _club_id: string
          _kind: Database["public"]["Enums"]["wallet_transaction_type"]
          _memo: string
          _ref_id: string
          _ref_table: string
        }
        Returns: number
      }
      admin_set_user_status: {
        Args: {
          _new_status: Database["public"]["Enums"]["user_status"]
          _reason?: string
          _target_user_id: string
        }
        Returns: {
          audit_log_id: string
          changed_at: string
          new_status: Database["public"]["Enums"]["user_status"]
          previous_status: Database["public"]["Enums"]["user_status"]
          target_user_id: string
        }[]
      }
      admin_get_season_setup: { Args: Record<PropertyKey, never>; Returns: Json }
      admin_set_season_participants: {
        Args: { _club_ids: string[]; _config_id: string }
        Returns: Json
      }
      admin_upsert_season_setup: {
        Args: { _config: Json }
        Returns: Json
      }
      buy_player_from_system: {
        Args: { _club_player_id: string }
        Returns: {
          balance_cents: number
          club_player_id: string
          player_id: string
          price_cents: number
          roster_size: number
        }[]
      }
      calculate_player_overall: {
        Args: {
          _defending: number
          _dribbling: number
          _finishing: number
          _goalkeeping: number
          _passing: number
          _physical: number
          _position: Database["public"]["Enums"]["player_position"]
          _velocity: number
        }
        Returns: number
      }
      calculate_reference_value_cents: {
        Args: {
          _overall: number
          _position: Database["public"]["Enums"]["player_position"]
          _rarity: Database["public"]["Enums"]["player_rarity"]
        }
        Returns: number
      }
      create_club: {
        Args: { _abbreviation: string; _badge_code: string; _name: string }
        Returns: string
      }
      has_role: {
        Args: {
          _role: Database["public"]["Enums"]["app_role"]
          _user_id: string
        }
        Returns: boolean
      }
      get_current_round_state: { Args: Record<PropertyKey, never>; Returns: Json }
      get_season_history: { Args: Record<PropertyKey, never>; Returns: Json }
      get_season_operational_state: { Args: Record<PropertyKey, never>; Returns: Json }
      get_season_standings: {
        Args: { _season_id?: string }
        Returns: {
          abbreviation: string
          club_id: string
          club_name: string
          draws: number
          goal_difference: number
          goals_against: number
          goals_for: number
          losses: number
          played: number
          points: number
          position: number
          wins: number
        }[]
      }
      is_approved_user: { Args: { _user_id?: string }; Returns: boolean }
      list_season_club_eligibility: {
        Args: { _include_private?: boolean }
        Returns: {
          abbreviation: string
          club_id: string
          club_name: string
          ineligible_reason: string | null
          is_eligible: boolean
          owner_id: string | null
          owner_username: string | null
        }[]
      }
      list_match_score_summaries: {
        Args: { _match_id?: string }
        Returns: {
          away_club_abbreviation: string
          away_club_badge_path: string
          away_club_id: string
          away_club_name: string
          away_goals: number
          competition_name: string
          final_result: string
          home_club_abbreviation: string
          home_club_badge_path: string
          home_club_id: string
          home_club_name: string
          home_goals: number
          match_id: string
          round_number: number
          starts_at: string
          status: Database["public"]["Enums"]["match_status"]
        }[]
      }
      normalize_club_name: { Args: { _name: string }; Returns: string }
      open_initial_pack: {
        Args: { _club_id: string }
        Returns: {
          club_id: string
          opened_at: string
          pack_id: string
          player_id: string
          slot: number
        }[]
      }
      save_lineup: {
        Args: {
          _formation: Database["public"]["Enums"]["formation"]
          _play_style: Database["public"]["Enums"]["play_style"]
          _players: Json
          _round_id: string
        }
        Returns: {
          club_id: string
          formation: Database["public"]["Enums"]["formation"]
          lineup_id: string
          play_style: Database["public"]["Enums"]["play_style"]
          player_count: number
          round_id: string
          saved_at: string
          starter_count: number
        }[]
      }
      sell_player_to_system: {
        Args: { _club_player_id: string }
        Returns: {
          balance_cents: number
          club_player_id: string
          player_id: string
          price_cents: number
          roster_size: number
        }[]
      }
      season_finish: { Args: { _season_id?: string }; Returns: Json }
      season_start: { Args: { _config_id: string }; Returns: Json }
      train_club_player: {
        Args: { _attribute: string; _club_player_id: string }
        Returns: {
          attribute: string
          attribute_after: number
          attribute_before: number
          balance_cents: number
          club_player_id: string
          cost_cents: number
          overall_after: number
          overall_before: number
          player_id: string
          progress_after: number
          progress_before: number
          reference_value_after_cents: number
          reference_value_before_cents: number
          session_id: string
        }[]
      }
      training_cost_cents: {
        Args: { _rarity: Database["public"]["Enums"]["player_rarity"] }
        Returns: number
      }
      update_club_identity: {
        Args: {
          _abbreviation?: string
          _badge_code?: string
          _club_id: string
          _name?: string
        }
        Returns: {
          abbreviation: string
          badge_id: string
          club_id: string
          name: string
          normalized_name: string
          updated_at: string
        }[]
      }
      user_participates_in_match: {
        Args: { _match_id: string; _user_id: string }
        Returns: boolean
      }
    }
    Enums: {
      app_role: "admin" | "user"
      formation: "1-2-1-1" | "1-1-2-1" | "1-1-1-2" | "0-2-2-1"
      league_status: "setup" | "active" | "finished"
      market_listing_status: "open" | "sold" | "cancelled" | "expired"
      match_event_type:
        | "match_started"
        | "pressure"
        | "chance"
        | "shot"
        | "save"
        | "goal"
        | "halftime"
        | "match_finished"
      match_status: "scheduled" | "live" | "finished" | "cancelled"
      notification_type:
        | "account_approved"
        | "round_today"
        | "round_soon"
        | "round_result"
        | "offer_received"
        | "offer_accepted"
        | "offer_rejected"
        | "card_sold"
      play_style: "balanced" | "offensive" | "defensive"
      player_position: "GK" | "DEF" | "MID" | "ATA"
      player_rarity: "peba" | "paia" | "pika"
      player_sector:
        | "centro"
        | "cidade_nova"
        | "promissao"
        | "jaderlandia"
        | "uraim"
        | "jardim"
        | "flamboyant"
        | "angelim"
        | "camboata"
        | "buriti"
        | "laercio"
        | "bela_vista"
        | "nagibao"
        | "ipixuna"
        | "caipe"
        | "paulo_sexto"
        | "morada_do_sol"
        | "morada_do_vento"
        | "nova_conquista"
      transfer_offer_status:
        | "pending"
        | "accepted"
        | "rejected"
        | "cancelled"
        | "expired"
      user_status: "pending" | "approved" | "blocked"
      wallet_transaction_type:
        | "initial_credit"
        | "match_reward"
        | "season_prize"
        | "market_sale"
        | "market_purchase"
        | "system_sale"
        | "system_purchase"
        | "training_cost"
        | "transfer_cash"
        | "admin_adjustment"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      app_role: ["admin", "user"],
      formation: ["1-2-1-1", "1-1-2-1", "1-1-1-2", "0-2-2-1"],
      league_status: ["setup", "active", "finished"],
      market_listing_status: ["open", "sold", "cancelled", "expired"],
      match_event_type: [
        "match_started",
        "pressure",
        "chance",
        "shot",
        "save",
        "goal",
        "halftime",
        "match_finished",
      ],
      match_status: ["scheduled", "live", "finished", "cancelled"],
      notification_type: [
        "account_approved",
        "round_today",
        "round_soon",
        "round_result",
        "offer_received",
        "offer_accepted",
        "offer_rejected",
        "card_sold",
      ],
      play_style: ["balanced", "offensive", "defensive"],
      player_position: ["GK", "DEF", "MID", "ATA"],
      player_rarity: ["peba", "paia", "pika"],
      player_sector: [
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
      ],
      transfer_offer_status: [
        "pending",
        "accepted",
        "rejected",
        "cancelled",
        "expired",
      ],
      user_status: ["pending", "approved", "blocked"],
      wallet_transaction_type: [
        "initial_credit",
        "match_reward",
        "season_prize",
        "market_sale",
        "market_purchase",
        "system_sale",
        "system_purchase",
        "training_cost",
        "transfer_cash",
        "admin_adjustment",
      ],
    },
  },
} as const
