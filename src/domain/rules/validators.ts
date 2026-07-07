/**
 * Pure input validators. Zero database or React dependencies.
 * These mirror server-side constraints and must stay aligned.
 */

export const USERNAME_REGEX = /^[A-Za-z0-9]{3,16}$/;
export const CLUB_ABBR_REGEX = /^[A-Z]{2,4}$/;

export type ValidationResult = { ok: true } | { ok: false; error: string };

export function validateUsername(input: string): ValidationResult {
  if (typeof input !== "string") return { ok: false, error: "username_required" };
  if (!USERNAME_REGEX.test(input)) return { ok: false, error: "username_invalid_format" };
  return { ok: true };
}

export function validatePassword(input: string): ValidationResult {
  if (typeof input !== "string") return { ok: false, error: "password_required" };
  if (input.length < 8 || input.length > 32) return { ok: false, error: "password_length" };
  if (!/[A-Za-z]/.test(input)) return { ok: false, error: "password_missing_letter" };
  if (!/[0-9]/.test(input)) return { ok: false, error: "password_missing_number" };
  return { ok: true };
}

export function validateClubName(input: string): ValidationResult {
  if (typeof input !== "string") return { ok: false, error: "name_required" };
  const trimmed = input.trim();
  if (trimmed.length < 3 || trimmed.length > 24) return { ok: false, error: "name_length" };
  // letters (with accents), numbers, spaces; no special symbols
  if (!/^[\p{L}0-9 ]+$/u.test(trimmed)) return { ok: false, error: "name_invalid_chars" };
  return { ok: true };
}

export function validateAbbreviation(input: string): ValidationResult {
  if (typeof input !== "string") return { ok: false, error: "abbr_required" };
  const upper = input.toUpperCase();
  if (!CLUB_ABBR_REGEX.test(upper)) return { ok: false, error: "abbr_invalid_format" };
  return { ok: true };
}

export const MIN_PRICE_CENTS = 0;
export const MAX_PRICE_CENTS = 10_000; // R$ 100,00

export function validatePriceCents(input: number): ValidationResult {
  if (!Number.isInteger(input)) return { ok: false, error: "price_not_integer" };
  if (input < MIN_PRICE_CENTS || input > MAX_PRICE_CENTS) return { ok: false, error: "price_out_of_range" };
  return { ok: true };
}

export function centsToReal(cents: number): string {
  const value = (cents / 100).toFixed(2);
  return `R$ ${value.replace(".", ",")}`;
}

export function realToCents(real: number): number {
  return Math.round(real * 100);
}

/** Internal auth email — user never sees this. */
export function usernameToInternalEmail(username: string): string {
  return `${username.toLowerCase()}@bagrefut.local`;
}
