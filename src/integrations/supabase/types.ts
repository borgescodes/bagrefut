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
          event_index: number | null
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
          event_index?: number | null
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
          event_index?: number | null
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
      match_lineup_snapshots: {
        Row: {
          attributes: Json
          base_overall: number
          club_id: string
          club_player_id: string
          created_at: string
          effective_overall: number
          formation: Database["public"]["Enums"]["formation"]
          id: string
          improvisation_penalty: number
          lineup_origin: string
          match_id: string
          natural_position: Database["public"]["Enums"]["player_position"]
          play_style: Database["public"]["Enums"]["play_style"]
          player_id: string
          slot_index: number
          used_position: Database["public"]["Enums"]["player_position"]
        }
        Insert: {
          attributes: Json
          base_overall: number
          club_id: string
          club_player_id: string
          created_at?: string
          effective_overall: number
          formation: Database["public"]["Enums"]["formation"]
          id?: string
          improvisation_penalty: number
          lineup_origin: string
          match_id: string
          natural_position: Database["public"]["Enums"]["player_position"]
          play_style: Database["public"]["Enums"]["play_style"]
          player_id: string
          slot_index: number
          used_position: Database["public"]["Enums"]["player_position"]
        }
        Update: {
          attributes?: Json
          base_overall?: number
          club_id?: string
          club_player_id?: string
          created_at?: string
          effective_overall?: number
          formation?: Database["public"]["Enums"]["formation"]
          id?: string
          improvisation_penalty?: number
          lineup_origin?: string
          match_id?: string
          natural_position?: Database["public"]["Enums"]["player_position"]
          play_style?: Database["public"]["Enums"]["play_style"]
          player_id?: string
          slot_index?: number
          used_position?: Database["public"]["Enums"]["player_position"]
        }
        Relationships: [
          {
            foreignKeyName: "match_lineup_snapshots_club_id_fkey"
            columns: ["club_id"]
            isOneToOne: false
            referencedRelation: "clubs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "match_lineup_snapshots_club_player_id_fkey"
            columns: ["club_player_id"]
            isOneToOne: false
            referencedRelation: "club_players"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "match_lineup_snapshots_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "match_lineup_snapshots_player_id_fkey"
            columns: ["player_id"]
            isOneToOne: false
            referencedRelation: "players"
            referencedColumns: ["id"]
          },
        ]
      }
      match_reward_config: {
        Row: {
          draw_cents: number
          id: boolean
          loss_cents: number
          updated_at: string
          win_cents: number
        }
        Insert: {
          draw_cents?: number
          id?: boolean
          loss_cents?: number
          updated_at?: string
          win_cents?: number
        }
        Update: {
          draw_cents?: number
          id?: boolean
          loss_cents?: number
          updated_at?: string
          win_cents?: number
        }
        Relationships: []
      }
      match_statistics: {
        Row: {
          attack_strength: number
          chances: number
          club_id: string
          created_at: string
          defense_strength: number
          formation: Database["public"]["Enums"]["formation"]
          goalkeeper_strength: number
          goals: number
          lineup_origin: string
          match_id: string
          overall_strength: number
          play_style: Database["public"]["Enums"]["play_style"]
          possession: number
          saves: number
          shots: number
          shots_on_target: number
        }
        Insert: {
          attack_strength: number
          chances?: number
          club_id: string
          created_at?: string
          defense_strength: number
          formation: Database["public"]["Enums"]["formation"]
          goalkeeper_strength: number
          goals?: number
          lineup_origin: string
          match_id: string
          overall_strength: number
          play_style: Database["public"]["Enums"]["play_style"]
          possession?: number
          saves?: number
          shots?: number
          shots_on_target?: number
        }
        Update: {
          attack_strength?: number
          chances?: number
          club_id?: string
          created_at?: string
          defense_strength?: number
          formation?: Database["public"]["Enums"]["formation"]
          goalkeeper_strength?: number
          goals?: number
          lineup_origin?: string
          match_id?: string
          overall_strength?: number
          play_style?: Database["public"]["Enums"]["play_style"]
          possession?: number
          saves?: number
          shots?: number
          shots_on_target?: number
        }
        Relationships: [
          {
            foreignKeyName: "match_statistics_club_id_fkey"
            columns: ["club_id"]
            isOneToOne: false
            referencedRelation: "clubs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "match_statistics_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
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
          scheduled_at: string | null
          seed: number | null
          simulated_at: string | null
          simulation_seed: string | null
          simulation_version: number | null
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
          scheduled_at?: string | null
          seed?: number | null
          simulated_at?: string | null
          simulation_seed?: string | null
          simulation_version?: number | null
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
          scheduled_at?: string | null
          seed?: number | null
          simulated_at?: string | null
          simulation_seed?: string | null
          simulation_version?: number | null
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
      operational_job_runs: {
        Row: {
          attempt_count: number
          created_at: string
          finished_at: string | null
          id: string
          job_type: string
          last_error: string | null
          max_attempts: number
          next_retry_at: string | null
          result: Json | null
          scheduled_for: string
          started_at: string | null
          status: string
          target_id: string
          updated_at: string
        }
        Insert: {
          attempt_count?: number
          created_at?: string
          finished_at?: string | null
          id?: string
          job_type: string
          last_error?: string | null
          max_attempts?: number
          next_retry_at?: string | null
          result?: Json | null
          scheduled_for: string
          started_at?: string | null
          status?: string
          target_id: string
          updated_at?: string
        }
        Update: {
          attempt_count?: number
          created_at?: string
          finished_at?: string | null
          id?: string
          job_type?: string
          last_error?: string | null
          max_attempts?: number
          next_retry_at?: string | null
          result?: Json | null
          scheduled_for?: string
          started_at?: string | null
          status?: string
          target_id?: string
          updated_at?: string
        }
        Relationships: []
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
          finalized_at: string | null
          id: string
          is_processed: boolean
          lineup_lock_at: string
          lineups_locked_at: string | null
          round_number: number
          season_id: string
          simulation_started_at: string | null
          starts_at: string
        }
        Insert: {
          ends_at: string
          finalized_at?: string | null
          id?: string
          is_processed?: boolean
          lineup_lock_at: string
          lineups_locked_at?: string | null
          round_number: number
          season_id: string
          simulation_started_at?: string | null
          starts_at: string
        }
        Update: {
          ends_at?: string
          finalized_at?: string | null
          id?: string
          is_processed?: boolean
          lineup_lock_at?: string
          lineups_locked_at?: string | null
          round_number?: number
          season_id?: string
          simulation_started_at?: string | null
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
      season_config_participants: {
        Row: {
          club_id: string
          config_id: string
          created_at: string
          sort_order: number
        }
        Insert: {
          club_id: string
          config_id: string
          created_at?: string
          sort_order: number
        }
        Update: {
          club_id?: string
          config_id?: string
          created_at?: string
          sort_order?: number
        }
        Relationships: [
          {
            foreignKeyName: "season_config_participants_club_id_fkey"
            columns: ["club_id"]
            isOneToOne: false
            referencedRelation: "clubs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "season_config_participants_config_id_fkey"
            columns: ["config_id"]
            isOneToOne: false
            referencedRelation: "season_configurations"
            referencedColumns: ["id"]
          },
        ]
      }
      season_configurations: {
        Row: {
          created_at: string
          created_by: string | null
          default_match_time: string
          id: string
          league_id: string
          name: string
          registration_deadline: string | null
          registration_status: string
          round_interval_days: number
          season_id: string | null
          start_date: string
          status: string
          timezone: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          default_match_time: string
          id?: string
          league_id: string
          name: string
          registration_deadline?: string | null
          registration_status?: string
          round_interval_days?: number
          season_id?: string | null
          start_date: string
          status?: string
          timezone?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          default_match_time?: string
          id?: string
          league_id?: string
          name?: string
          registration_deadline?: string | null
          registration_status?: string
          round_interval_days?: number
          season_id?: string | null
          start_date?: string
          status?: string
          timezone?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "season_configurations_league_id_fkey"
            columns: ["league_id"]
            isOneToOne: false
            referencedRelation: "leagues"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "season_configurations_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: true
            referencedRelation: "seasons"
            referencedColumns: ["id"]
          },
        ]
      }
      season_final_standings: {
        Row: {
          club_id: string
          created_at: string
          draws: number
          goal_difference: number
          goals_against: number
          goals_for: number
          losses: number
          played: number
          points: number
          position: number
          prize_cents: number
          season_id: string
          wins: number
        }
        Insert: {
          club_id: string
          created_at?: string
          draws: number
          goal_difference: number
          goals_against: number
          goals_for: number
          losses: number
          played: number
          points: number
          position: number
          prize_cents?: number
          season_id: string
          wins: number
        }
        Update: {
          club_id?: string
          created_at?: string
          draws?: number
          goal_difference?: number
          goals_against?: number
          goals_for?: number
          losses?: number
          played?: number
          points?: number
          position?: number
          prize_cents?: number
          season_id?: string
          wins?: number
        }
        Relationships: [
          {
            foreignKeyName: "season_final_standings_club_id_fkey"
            columns: ["club_id"]
            isOneToOne: false
            referencedRelation: "clubs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "season_final_standings_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: false
            referencedRelation: "seasons"
            referencedColumns: ["id"]
          },
        ]
      }
      season_participants: {
        Row: {
          club_id: string
          created_at: string
          season_id: string
          sort_order: number
        }
        Insert: {
          club_id: string
          created_at?: string
          season_id: string
          sort_order: number
        }
        Update: {
          club_id?: string
          created_at?: string
          season_id?: string
          sort_order?: number
        }
        Relationships: [
          {
            foreignKeyName: "season_participants_club_id_fkey"
            columns: ["club_id"]
            isOneToOne: false
            referencedRelation: "clubs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "season_participants_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: false
            referencedRelation: "seasons"
            referencedColumns: ["id"]
          },
        ]
      }
      season_prize_config: {
        Row: {
          amount_cents: number
          config_id: string
          created_at: string
          position: number
        }
        Insert: {
          amount_cents: number
          config_id: string
          created_at?: string
          position: number
        }
        Update: {
          amount_cents?: number
          config_id?: string
          created_at?: string
          position?: number
        }
        Relationships: [
          {
            foreignKeyName: "season_prize_config_config_id_fkey"
            columns: ["config_id"]
            isOneToOne: false
            referencedRelation: "season_configurations"
            referencedColumns: ["id"]
          },
        ]
      }
      seasons: {
        Row: {
          champion_club_id: string | null
          champion_goal_difference: number | null
          champion_points: number | null
          champion_wins: number | null
          config_id: string | null
          created_at: string
          finished_at: string | null
          id: string
          league_id: string
          name: string | null
          season_number: number
          seed: number
          started_at: string | null
          status: string
          updated_at: string
        }
        Insert: {
          champion_club_id?: string | null
          champion_goal_difference?: number | null
          champion_points?: number | null
          champion_wins?: number | null
          config_id?: string | null
          created_at?: string
          finished_at?: string | null
          id?: string
          league_id: string
          name?: string | null
          season_number: number
          seed?: number
          started_at?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          champion_club_id?: string | null
          champion_goal_difference?: number | null
          champion_points?: number | null
          champion_wins?: number | null
          config_id?: string | null
          created_at?: string
          finished_at?: string | null
          id?: string
          league_id?: string
          name?: string | null
          season_number?: number
          seed?: number
          started_at?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "seasons_champion_club_id_fkey"
            columns: ["champion_club_id"]
            isOneToOne: false
            referencedRelation: "clubs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "seasons_config_id_fkey"
            columns: ["config_id"]
            isOneToOne: false
            referencedRelation: "season_configurations"
            referencedColumns: ["id"]
          },
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
      _assert_approved_admin: { Args: never; Returns: string }
      _bagreleirao_league_id: { Args: never; Returns: string }
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
      _expire_transfer_offers: { Args: { _now?: string }; Returns: number }
      _match_clamp: {
        Args: { _max: number; _min: number; _value: number }
        Returns: number
      }
      _match_credit_reward: {
        Args: {
          _club_id: string
          _goals_against: number
          _goals_for: number
          _match_id: string
        }
        Returns: undefined
      }
      _match_formation_modifier: {
        Args: {
          _formation: Database["public"]["Enums"]["formation"]
          _key: string
        }
        Returns: number
      }
      _match_formation_slots: {
        Args: { _formation: Database["public"]["Enums"]["formation"] }
        Returns: {
          slot_index: number
          slot_order: number
          slot_position: Database["public"]["Enums"]["player_position"]
        }[]
      }
      _match_improvisation_multiplier: {
        Args: {
          _natural: Database["public"]["Enums"]["player_position"]
          _used: Database["public"]["Enums"]["player_position"]
        }
        Returns: number
      }
      _match_insert_event: {
        Args: {
          _away_goals: number
          _club_id: string
          _event_index: number
          _event_type: Database["public"]["Enums"]["match_event_type"]
          _home_goals: number
          _match_id: string
          _meta: Json
          _minute: number
          _player_id: string
        }
        Returns: undefined
      }
      _match_result_json: { Args: { _match_id: string }; Returns: Json }
      _match_sim_random: {
        Args: { _counter: number; _seed: string }
        Returns: number
      }
      _match_simulate_internal: { Args: { _match_id: string }; Returns: Json }
      _match_strength: {
        Args: { _club_id: string; _match_id: string }
        Returns: {
          attack_strength: number
          defense_strength: number
          goalkeeper_strength: number
          overall_strength: number
        }[]
      }
      _match_style_modifier: {
        Args: {
          _key: string
          _style: Database["public"]["Enums"]["play_style"]
        }
        Returns: number
      }
      _operational_process_job: {
        Args: {
          _job_type: string
          _now: string
          _scheduled_for: string
          _target_id: string
        }
        Returns: Json
      }
      _operational_retry_delay: {
        Args: { _attempt_count: number }
        Returns: string
      }
      _operational_retry_job_run: {
        Args: { _job_run_id: string }
        Returns: Json
      }
      _release_transfer_offer_cards: {
        Args: { _offer_id: string }
        Returns: number
      }
      _round_finalize_internal: { Args: { _round_id: string }; Returns: Json }
      _round_simulate_internal: { Args: { _round_id: string }; Returns: Json }
      _season_club_eligibility: {
        Args: { _league_id: string }
        Returns: {
          abbreviation: string
          club_id: string
          club_name: string
          ineligible_reason: string
          is_eligible: boolean
          owner_id: string
          owner_username: string
        }[]
      }
      _season_finish_internal: { Args: { _season_id?: string }; Returns: Json }
      _validate_season_config: {
        Args: { _config_id: string }
        Returns: undefined
      }
      accept_transfer_offer: {
        Args: { _offer_id: string }
        Returns: {
          idempotent: boolean
          offer_id: string
          resolved_at: string
          status: Database["public"]["Enums"]["transfer_offer_status"]
        }[]
      }
      admin_get_season_setup: { Args: never; Returns: Json }
      admin_list_operational_job_runs: {
        Args: { _limit?: number; _status?: string }
        Returns: {
          attempt_count: number
          created_at: string
          finished_at: string
          id: string
          job_type: string
          last_error: string
          max_attempts: number
          next_retry_at: string
          result: Json
          scheduled_for: string
          started_at: string
          status: string
          target_id: string
          updated_at: string
        }[]
      }
      admin_set_season_participants: {
        Args: { _club_ids: string[]; _config_id: string }
        Returns: Json
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
      admin_upsert_season_setup: { Args: { _config: Json }; Returns: Json }
      buy_market_listing: {
        Args: { _listing_id: string }
        Returns: {
          buyer_balance_cents: number
          buyer_roster_size: number
          club_player_id: string
          idempotent: boolean
          listing_id: string
          price_cents: number
          seller_balance_cents: number
          seller_roster_size: number
          status: Database["public"]["Enums"]["market_listing_status"]
        }[]
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
      cancel_market_listing: {
        Args: { _listing_id: string }
        Returns: {
          club_player_id: string
          idempotent: boolean
          is_reserved: boolean
          listing_id: string
          price_cents: number
          status: Database["public"]["Enums"]["market_listing_status"]
        }[]
      }
      cancel_transfer_offer: {
        Args: { _offer_id: string }
        Returns: {
          idempotent: boolean
          offer_id: string
          resolved_at: string
          status: Database["public"]["Enums"]["transfer_offer_status"]
        }[]
      }
      create_club: {
        Args: { _abbreviation: string; _badge_code: string; _name: string }
        Returns: string
      }
      create_market_listing: {
        Args: { _club_player_id: string; _price_cents: number }
        Returns: {
          club_player_id: string
          idempotent: boolean
          is_reserved: boolean
          listing_id: string
          price_cents: number
          status: Database["public"]["Enums"]["market_listing_status"]
        }[]
      }
      create_transfer_offer: {
        Args: {
          _cash_cents?: number
          _expires_at?: string
          _from_club_player_ids: string[]
          _to_club_id: string
          _to_club_player_ids: string[]
        }
        Returns: {
          expires_at: string
          idempotent: boolean
          offer_id: string
          reserved_count: number
          status: Database["public"]["Enums"]["transfer_offer_status"]
        }[]
      }
      get_current_round_state: { Args: never; Returns: Json }
      get_match_public_details: { Args: { _match_id: string }; Returns: Json }
      get_season_history: { Args: never; Returns: Json }
      get_season_operational_state: { Args: never; Returns: Json }
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
      get_trade_target_roster: {
        Args: { _club_id: string }
        Returns: {
          club_player_id: string
          defending: number
          dribbling: number
          finishing: number
          goalkeeping: number
          overall: number
          passing: number
          physical: number
          player_id: string
          player_name: string
          position: Database["public"]["Enums"]["player_position"]
          rarity: Database["public"]["Enums"]["player_rarity"]
          reference_value_cents: number
          sector: Database["public"]["Enums"]["player_sector"]
          velocity: number
        }[]
      }
      has_role: {
        Args: {
          _role: Database["public"]["Enums"]["app_role"]
          _user_id: string
        }
        Returns: boolean
      }
      is_approved_user: { Args: { _user_id?: string }; Returns: boolean }
      list_market_listings: {
        Args: {
          _max_overall?: number
          _max_price_cents?: number
          _min_overall?: number
          _position?: Database["public"]["Enums"]["player_position"]
          _rarity?: Database["public"]["Enums"]["player_rarity"]
        }
        Returns: {
          club_player_id: string
          created_at: string
          defending: number
          dribbling: number
          finishing: number
          goalkeeping: number
          is_mine: boolean
          listing_id: string
          overall: number
          passing: number
          physical: number
          player_id: string
          player_name: string
          position: Database["public"]["Enums"]["player_position"]
          price_cents: number
          rarity: Database["public"]["Enums"]["player_rarity"]
          reference_value_cents: number
          sector: Database["public"]["Enums"]["player_sector"]
          seller_abbreviation: string
          seller_club_id: string
          seller_name: string
          velocity: number
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
      list_my_transfer_offers: {
        Args: never
        Returns: {
          can_accept: boolean
          can_cancel: boolean
          can_reject: boolean
          cash_cents: number
          created_at: string
          direction: string
          expires_at: string
          from_cards: Json
          from_club: Json
          offer_id: string
          resolved_at: string
          status: Database["public"]["Enums"]["transfer_offer_status"]
          to_cards: Json
          to_club: Json
        }[]
      }
      list_season_club_eligibility: {
        Args: { _include_private?: boolean }
        Returns: {
          abbreviation: string
          club_id: string
          club_name: string
          ineligible_reason: string
          is_eligible: boolean
          owner_id: string
          owner_username: string
        }[]
      }
      list_trade_targets: {
        Args: never
        Returns: {
          abbreviation: string
          club_id: string
          name: string
          roster_size: number
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
      process_due_rounds: { Args: { _now?: string }; Returns: Json }
      reject_transfer_offer: {
        Args: { _offer_id: string }
        Returns: {
          idempotent: boolean
          offer_id: string
          resolved_at: string
          status: Database["public"]["Enums"]["transfer_offer_status"]
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
      season_finish: { Args: { _season_id?: string }; Returns: Json }
      season_start: { Args: { _config_id: string }; Returns: Json }
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
      simulate_match: { Args: { _match_id: string }; Returns: Json }
      simulate_round: { Args: { _round_id: string }; Returns: Json }
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
