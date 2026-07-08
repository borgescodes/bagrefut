import { describe, expect, it } from "vitest";
import {
  buildPasswordRecoveryWhatsAppMessage,
  buildPasswordRecoveryWhatsAppUrl,
  mapAuthErrorMessage,
  PASSWORD_RECOVERY_WHATSAPP_NUMBER,
} from "@/domain/rules/auth";
import {
  buildPasswordResetAppMetadata,
  buildPasswordResetAuditPayload,
  generateTemporaryPassword,
  TEMPORARY_PASSWORD_MIN_LENGTH,
} from "@/lib/admin.functions";
import { validatePassword } from "@/domain/rules/validators";

describe("password recovery WhatsApp helpers", () => {
  it("uses the normalized WhatsApp number", () => {
    expect(PASSWORD_RECOVERY_WHATSAPP_NUMBER).toBe("5591987338595");
  });

  it("builds a wa.me URL for the normalized number", () => {
    expect(buildPasswordRecoveryWhatsAppUrl()).toMatch(/^https:\/\/wa\.me\/5591987338595/);
  });

  it("builds a message with username", () => {
    expect(buildPasswordRecoveryWhatsAppMessage(" Bagre123 ")).toBe(
      "Olá! Preciso recuperar minha senha do BagreFut. Meu usuário é: bagre123.",
    );
  });

  it("builds a message without username", () => {
    expect(buildPasswordRecoveryWhatsAppMessage()).toBe(
      "Olá! Preciso recuperar minha senha do BagreFut. Meu usuário é: [informe seu usuário].",
    );
  });

  it("encodes special characters in the URL message", () => {
    const url = buildPasswordRecoveryWhatsAppUrl("Bagre 10+");

    expect(url).toContain("text=");
    expect(url).toContain(encodeURIComponent("bagre 10+"));
    expect(url).not.toContain("Bagre 10+");
  });
});

describe("auth error mapper", () => {
  it("maps known Supabase auth messages to pt-BR", () => {
    expect(mapAuthErrorMessage("Invalid login credentials")).toBe("Usuário ou senha inválidos.");
    expect(mapAuthErrorMessage("User not found")).toBe("Usuário ou senha inválidos.");
    expect(mapAuthErrorMessage("Email not confirmed")).toBe("Conta ainda não liberada para login.");
    expect(mapAuthErrorMessage("Too many requests")).toBe(
      "Muitas tentativas. Tente novamente mais tarde.",
    );
  });

  it("maps unknown auth messages to a generic pt-BR error", () => {
    expect(mapAuthErrorMessage("some raw provider error")).toBe(
      "Não foi possível concluir. Tente novamente.",
    );
  });
});

describe("temporary password generation", () => {
  it("generates a password with minimum length", () => {
    expect(generateTemporaryPassword()).toHaveLength(TEMPORARY_PASSWORD_MIN_LENGTH);
  });

  it("generates a password with uppercase, lowercase and number", () => {
    const password = generateTemporaryPassword();

    expect(/[A-Z]/.test(password)).toBe(true);
    expect(/[a-z]/.test(password)).toBe(true);
    expect(/[0-9]/.test(password)).toBe(true);
  });

  it("generates a password that passes shared validation", () => {
    expect(validatePassword(generateTemporaryPassword()).ok).toBe(true);
  });
});

describe("temporary password metadata and audit helpers", () => {
  it("preserves existing app_metadata when marking password change required", () => {
    expect(buildPasswordResetAppMetadata({ provider: "email", roles: ["admin"] })).toEqual({
      provider: "email",
      roles: ["admin"],
      must_change_password: true,
    });
  });

  it("builds audit payload without the temporary password", () => {
    const tempPassword = "Astrong12345";
    const payload = buildPasswordResetAuditPayload();

    expect(payload).toEqual({
      result: "temporary_password_created",
      must_change_password: true,
    });
    expect(JSON.stringify(payload)).not.toContain(tempPassword);
  });
});
