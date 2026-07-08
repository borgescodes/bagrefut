export const PASSWORD_RECOVERY_WHATSAPP_NUMBER = "5591987338595";

function normalizeRecoveryUsername(username?: string): string {
  return (username ?? "").trim().toLowerCase();
}

export function buildPasswordRecoveryWhatsAppMessage(username?: string): string {
  const normalized = normalizeRecoveryUsername(username);
  const displayUsername = normalized.length > 0 ? normalized : "[informe seu usuário]";
  return `Olá! Preciso recuperar minha senha do BagreFut. Meu usuário é: ${displayUsername}.`;
}

export function buildPasswordRecoveryWhatsAppUrl(username?: string): string {
  return `https://wa.me/${PASSWORD_RECOVERY_WHATSAPP_NUMBER}?text=${encodeURIComponent(
    buildPasswordRecoveryWhatsAppMessage(username),
  )}`;
}

export function mapAuthErrorMessage(message?: string | null): string {
  if (!message) return "Não foi possível concluir. Tente novamente.";
  if (message.includes("Invalid login credentials")) return "Usuário ou senha inválidos.";
  if (message.includes("User not found")) return "Usuário ou senha inválidos.";
  if (message.includes("Email not confirmed")) return "Conta ainda não liberada para login.";
  if (message.includes("Too many requests"))
    return "Muitas tentativas. Tente novamente mais tarde.";
  return "Não foi possível concluir. Tente novamente.";
}
