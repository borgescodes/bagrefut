import { describe, expect, it } from "vitest";
import {
  centsToReal,
  MAX_PRICE_CENTS,
  validateAbbreviation,
  validateClubName,
  validatePassword,
  validatePasswordConfirmation,
  validatePriceCents,
  validateUsername,
} from "@/domain/rules/validators";

describe("validateUsername", () => {
  it("accepts valid usernames", () => {
    expect(validateUsername("bagre").ok).toBe(true);
    expect(validateUsername("Bagre123").ok).toBe(true);
    expect(validateUsername("a1b2c3d4e5f6g7h8").ok).toBe(true); // 16 chars
  });
  it("rejects invalid usernames", () => {
    expect(validateUsername("ab").ok).toBe(false); // too short
    expect(validateUsername("a".repeat(17)).ok).toBe(false); // too long
    expect(validateUsername("bagre_fut").ok).toBe(false); // underscore
    expect(validateUsername("bagré").ok).toBe(false); // accent
    expect(validateUsername("bagre fut").ok).toBe(false); // space
  });
});

describe("validatePassword", () => {
  it("accepts passwords with a letter and a number in range", () => {
    expect(validatePassword("abcd1234").ok).toBe(true);
    expect(validatePassword("A1".padEnd(32, "x1")).ok).toBe(true);
  });
  it("rejects passwords missing complexity", () => {
    expect(validatePassword("short1").ok).toBe(false);
    expect(validatePassword("onlyletters").ok).toBe(false);
    expect(validatePassword("12345678").ok).toBe(false);
    expect(validatePassword("a".repeat(33) + "1").ok).toBe(false);
  });
});

describe("validatePasswordConfirmation", () => {
  it("accepts matching passwords", () => {
    expect(validatePasswordConfirmation("abcd1234", "abcd1234").ok).toBe(true);
  });

  it("rejects empty confirmation", () => {
    expect(validatePasswordConfirmation("abcd1234", "")).toEqual({
      ok: false,
      error: "password_confirmation_required",
    });
  });

  it("rejects different confirmation", () => {
    expect(validatePasswordConfirmation("abcd1234", "abcd12345")).toEqual({
      ok: false,
      error: "password_confirmation_mismatch",
    });
  });
});

describe("validateClubName / abbreviation", () => {
  it("accepts and normalizes valid inputs", () => {
    expect(validateClubName("Bagre FC").ok).toBe(true);
    expect(validateClubName("Águia do Norte").ok).toBe(true);
    expect(validateAbbreviation("bfc").ok).toBe(true); // will be uppercased
  });
  it("rejects invalid inputs", () => {
    expect(validateClubName("AB").ok).toBe(false);
    expect(validateClubName("Bagre@FC").ok).toBe(false);
    expect(validateAbbreviation("A").ok).toBe(false);
    expect(validateAbbreviation("TOOLONG").ok).toBe(false);
    expect(validateAbbreviation("BC1").ok).toBe(false);
  });
});

describe("validatePriceCents / formatting", () => {
  it("accepts the full 0..10000 cents range", () => {
    expect(validatePriceCents(0).ok).toBe(true);
    expect(validatePriceCents(MAX_PRICE_CENTS).ok).toBe(true);
  });
  it("rejects out-of-range or non-integer values", () => {
    expect(validatePriceCents(-1).ok).toBe(false);
    expect(validatePriceCents(10_001).ok).toBe(false);
    expect(validatePriceCents(1.5).ok).toBe(false);
  });
  it("formats cents to BRL string", () => {
    expect(centsToReal(0)).toBe("R$ 0,00");
    expect(centsToReal(100)).toBe("R$ 1,00");
    expect(centsToReal(2550)).toBe("R$ 25,50");
    expect(centsToReal(10000)).toBe("R$ 100,00");
  });
});
