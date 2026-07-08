import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const checkerPath = path.join(repoRoot, "scripts", "check-package-manager.mjs");

function withPackageFixture(files: Record<string, string>, run: (cwd: string) => void) {
  const cwd = mkdtempSync(path.join(tmpdir(), "bagrefut-pm-check-"));
  try {
    for (const [name, contents] of Object.entries(files)) {
      writeFileSync(path.join(cwd, name), contents);
    }
    run(cwd);
  } finally {
    rmSync(cwd, { recursive: true, force: true });
  }
}

function runChecker(cwd: string) {
  return spawnSync(process.execPath, [checkerPath], {
    cwd,
    encoding: "utf8",
  });
}

describe("check-package-manager script", () => {
  it("accepts bun.lock as the only lockfile with bun packageManager", () => {
    withPackageFixture(
      {
        "package.json": JSON.stringify({ packageManager: "bun@1.3.14" }),
        "bun.lock": "",
      },
      (cwd) => {
        const result = runChecker(cwd);

        expect(result.status).toBe(0);
        expect(result.stderr).toBe("");
      },
    );
  });

  it("fails when bun.lock is missing", () => {
    withPackageFixture(
      {
        "package.json": JSON.stringify({ packageManager: "bun@1.3.14" }),
      },
      (cwd) => {
        const result = runChecker(cwd);

        expect(result.status).toBe(1);
        expect(result.stderr).toContain("bun.lock");
      },
    );
  });

  it("fails when a concurrent lockfile exists", () => {
    withPackageFixture(
      {
        "package.json": JSON.stringify({ packageManager: "bun@1.3.14" }),
        "bun.lock": "",
        "package-lock.json": "",
      },
      (cwd) => {
        const result = runChecker(cwd);

        expect(result.status).toBe(1);
        expect(result.stderr).toContain("package-lock.json");
      },
    );
  });

  it("fails when packageManager is not bun", () => {
    withPackageFixture(
      {
        "package.json": JSON.stringify({ packageManager: "npm@11.0.0" }),
        "bun.lock": "",
      },
      (cwd) => {
        const result = runChecker(cwd);

        expect(result.status).toBe(1);
        expect(result.stderr).toContain("packageManager");
      },
    );
  });
});
