const MARKET_ERROR_MESSAGES: Record<string, string> = {
  unauthenticated: "Entre novamente para usar o mercado.",
  profile_not_approved: "Sua conta precisa estar aprovada para usar o mercado.",
  club_not_found: "Crie um clube antes de usar o mercado.",
  player_not_owned: "Esta carta não pertence ao seu clube.",
  player_reserved: "Esta carta está reservada em outra negociação.",
  card_reserved: "Esta carta está reservada em outra negociação.",
  player_already_listed: "Esta carta já está anunciada.",
  player_in_pending_offer: "Esta carta já participa de uma oferta pendente.",
  listing_not_found: "O anúncio não foi encontrado.",
  listing_not_open: "Este anúncio não está mais disponível.",
  cannot_buy_own_listing: "Você não pode comprar o próprio anúncio.",
  insufficient_balance: "Saldo insuficiente para concluir a operação.",
  insufficient_balance_or_club_missing: "Saldo insuficiente para concluir a operação.",
  roster_minimum: "O clube precisa permanecer com pelo menos 5 cartas.",
  roster_minimum_reached: "O clube precisa permanecer com pelo menos 5 cartas.",
  roster_maximum: "O clube pode ter no máximo 10 cartas.",
  roster_maximum_reached: "O clube pode ter no máximo 10 cartas.",
  offer_not_found: "A oferta não foi encontrada.",
  offer_not_pending: "Esta oferta não está mais pendente.",
  offer_expired: "Esta oferta expirou.",
  offer_not_recipient: "Somente o destinatário pode realizar esta ação.",
  offer_not_sender: "Somente o criador pode cancelar esta oferta.",
  duplicate_player: "A mesma carta não pode aparecer mais de uma vez.",
  invalid_price: "Informe um preço entre R$ 0,01 e R$ 100,00.",
  invalid_cash: "O dinheiro da oferta deve ficar entre R$ 0,00 e R$ 100,00.",
  daily_training_limit: "Seu clube já treinou hoje. Tente novamente amanhã.",
  training_already_done_today: "Seu clube já treinou hoje. Tente novamente amanhã.",
  attribute_invalid: "Escolha um atributo válido para o treino.",
  attribute_maxed: "Este atributo já atingiu o nível máximo.",
  wallet_balance_cap_exceeded: "A operação ultrapassaria o saldo máximo de R$ 999,99.",
  player_not_in_system_stock: "Esta carta não está mais disponível na vitrine do sistema.",
};

export function mapMarketErrorMessage(error: unknown): string {
  const message = readErrorMessage(error);
  const code = Object.keys(MARKET_ERROR_MESSAGES).find((candidate) => message.includes(candidate));
  return code ? MARKET_ERROR_MESSAGES[code] : "Não foi possível concluir a operação de mercado.";
}

function readErrorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (
    typeof error === "object" &&
    error !== null &&
    "message" in error &&
    typeof error.message === "string"
  ) {
    return error.message;
  }
  return String(error);
}
