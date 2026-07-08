import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const FORBIDDEN_LOCKFILES = [
  "package-lock.json",
  "npm-shrinkwrap.json",
  "pnpm-lock.yaml",
  "yarn.lock",
  "bun.lockb",
];

function readPackageJson(rootDir) {
  const packageJsonPath = path.join(rootDir, "package.json");
  try {
    return JSON.parse(readFileSync(packageJsonPath, "utf8"));
  } catch (error) {
    throw new Error(`package.json invalido ou ausente: ${error.message}`);
  }
}

export function validatePackageManagerPolicy(rootDir = process.cwd()) {
  const errors = [];

  if (!existsSync(path.join(rootDir, "bun.lock"))) {
    errors.push("bun.lock ausente. Rode bun install --frozen-lockfile.");
  }

  for (const lockfile of FORBIDDEN_LOCKFILES) {
    if (existsSync(path.join(rootDir, lockfile))) {
      errors.push(`${lockfile} nao permitido. Remova o lockfile concorrente.`);
    }
  }

  const packageJson = readPackageJson(rootDir);
  if (
    Object.prototype.hasOwnProperty.call(packageJson, "packageManager") &&
    (typeof packageJson.packageManager !== "string" ||
      !/^bun@\d+\.\d+\.\d+(?:[-+].+)?$/.test(packageJson.packageManager))
  ) {
    errors.push('packageManager deve usar o formato "bun@<versao>".');
  }

  return errors;
}

function main() {
  const errors = validatePackageManagerPolicy(process.cwd());
  if (errors.length > 0) {
    console.error(`package-manager check failed: ${errors.join(" ")}`);
    process.exit(1);
  }
}

const invokedPath = process.argv[1] ? pathToFileURL(path.resolve(process.argv[1])).href : "";
if (import.meta.url === invokedPath || fileURLToPath(import.meta.url) === process.argv[1]) {
  main();
}
