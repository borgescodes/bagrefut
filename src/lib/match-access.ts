import type { MatchScoreSummary } from "@/domain/types";

export interface MatchEventAccessInput {
  summary: MatchScoreSummary;
  myClubId: string | null | undefined;
  isAdmin: boolean;
}

export function canRequestMatchEvents({
  summary,
  myClubId,
  isAdmin,
}: MatchEventAccessInput): boolean {
  if (isAdmin) return true;
  if (!myClubId) return false;
  return summary.home_club_id === myClubId || summary.away_club_id === myClubId;
}

export function shouldFetchMatchEvents(input: MatchEventAccessInput): boolean {
  return canRequestMatchEvents(input);
}

export function mapMatchEventsErrorMessage(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);
  if (message.includes("match_events_forbidden")) {
    return "Eventos detalhados disponíveis somente para partidas do seu clube.";
  }
  if (message.includes("profile_not_approved")) {
    return "Sua conta ainda não está aprovada para ver partidas.";
  }
  if (message.includes("match_not_found")) {
    return "Partida não encontrada.";
  }
  if (message.includes("unauthenticated")) {
    return "Entre novamente para ver partidas.";
  }
  return "Não foi possível carregar os eventos da partida.";
}
