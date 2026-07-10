const MARKET_ERROR_MESSAGES: Record<string, string> = {
  unauthenticated: "Entre novamente para usar o mercado.",
  profile_not_approved: "Sua conta precisa estar aprovada para usar o mercado.",
  club_not_found: "Crie um clube antes de usar o mercado.",
  player_not_owned: "Esta carta nao pertence ao seu clube.",
  player_reserved: "Esta carta esta reservada em outra negociacao.",
  card_reserved: "Esta carta esta reservada em outra negociacao.",
  player_already_listed: "Esta carta ja esta anunciada.",
  player_in_pending_offer: "Esta carta ja participa de uma oferta pendente.",
  listing_not_found: "O anuncio nao foi encontrado.",
  listing_not_open: "Este anuncio nao esta mais disponivel.",
  cannot_buy_own_listing: "Voce nao pode comprar o proprio anuncio.",
  insufficient_balance: "Saldo insuficiente para concluir a operacao.",
  insufficient_balance_or_club_missing: "Saldo insuficiente para concluir a operacao.",
  roster_minimum: "O clube precisa permanecer com pelo menos 5 cartas.",
  roster_minimum_reached: "O clube precisa permanecer com pelo menos 5 cartas.",
  roster_maximum: "O clube pode ter no maximo 15 cartas.",
  roster_maximum_reached: "O clube pode ter no maximo 15 cartas.",
  offer_not_found: "A oferta nao foi encontrada.",
  offer_not_pending: "Esta oferta nao esta mais pendente.",
  offer_expired: "Esta oferta expirou.",
  offer_not_recipient: "Somente o destinatario pode realizar esta acao.",
  offer_not_sender: "Somente o criador pode cancelar esta oferta.",
  duplicate_player: "A mesma carta nao pode aparecer mais de uma vez.",
  invalid_price: "Informe um preco entre R$ 0,01 e R$ 100,00.",
  invalid_cash: "O dinheiro da oferta deve ficar entre R$ 0,00 e R$ 100,00.",
  daily_training_limit: "Seu clube ja treinou hoje. Tente novamente amanha.",
  training_already_done_today: "Seu clube ja treinou hoje. Tente novamente amanha.",
  attribute_invalid: "Escolha um atributo valido para o treino.",
  attribute_maxed: "Este atributo ja atingiu o nivel maximo.",
  wallet_balance_cap_exceeded: "A operacao ultrapassaria o saldo maximo de R$ 100,00.",
  player_not_in_system_stock: "Esta carta nao esta mais disponivel no sistema.",
};

export function mapMarketErrorMessage(error: unknown): string {
  const message = readErrorMessage(error);
  const code = Object.keys(MARKET_ERROR_MESSAGES).find((candidate) => message.includes(candidate));
  return code ? MARKET_ERROR_MESSAGES[code] : "Nao foi possivel concluir a operacao de mercado.";
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
