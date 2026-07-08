import { existsSync, readFileSync } from "node:fs";
import path from "node:path";

const PUBLIC_DIR = path.join(process.cwd(), "public");
const REQUIRED_ICONS = [
  { file: "pwa-192x192.png", width: 192, height: 192 },
  { file: "pwa-512x512.png", width: 512, height: 512 },
  { file: "pwa-maskable-192x192.png", width: 192, height: 192 },
  { file: "pwa-maskable-512x512.png", width: 512, height: 512 },
  { file: "apple-touch-icon.png", width: 180, height: 180 },
];

const REQUIRED_MANIFEST_ICON_SOURCES = [
  "/pwa-192x192.png",
  "/pwa-512x512.png",
  "/pwa-maskable-192x192.png",
  "/pwa-maskable-512x512.png",
];

function fail(message) {
  throw new Error(`PWA asset check failed: ${message}`);
}

function readPngDimensions(filePath) {
  const buffer = readFileSync(filePath);
  if (
    buffer.length < 24 ||
    buffer[0] !== 0x89 ||
    buffer[1] !== 0x50 ||
    buffer[2] !== 0x4e ||
    buffer[3] !== 0x47
  ) {
    fail(`${path.basename(filePath)} is not a PNG file`);
  }

  return {
    width: buffer.readUInt32BE(16),
    height: buffer.readUInt32BE(20),
  };
}

function readManifest() {
  const manifestPath = path.join(PUBLIC_DIR, "manifest.webmanifest");
  if (!existsSync(manifestPath)) fail("public/manifest.webmanifest is missing");
  return JSON.parse(readFileSync(manifestPath, "utf8"));
}

function assertManifest(manifest) {
  const expected = {
    name: "BagreFut",
    short_name: "BagreFut",
    description: "Jogo privado de gerenciamento de futebol.",
    lang: "pt-BR",
    start_url: "/",
    scope: "/",
    display: "standalone",
    orientation: "portrait",
  };

  for (const [key, value] of Object.entries(expected)) {
    if (manifest[key] !== value) fail(`manifest.${key} must be ${JSON.stringify(value)}`);
  }

  if (!/^#[0-9a-fA-F]{6}$/.test(manifest.theme_color)) {
    fail("manifest.theme_color must be a hex RGB color");
  }
  if (!/^#[0-9a-fA-F]{6}$/.test(manifest.background_color)) {
    fail("manifest.background_color must be a hex RGB color");
  }

  const icons = Array.isArray(manifest.icons) ? manifest.icons : [];
  for (const src of REQUIRED_MANIFEST_ICON_SOURCES) {
    const icon = icons.find((candidate) => candidate?.src === src);
    if (!icon) fail(`manifest icon ${src} is missing`);
    if (icon.type !== "image/png") fail(`manifest icon ${src} must be image/png`);
    if (!icon.sizes || !/^\d+x\d+$/.test(icon.sizes)) {
      fail(`manifest icon ${src} must declare sizes`);
    }
    if (src.includes("maskable") && icon.purpose !== "maskable") {
      fail(`manifest icon ${src} must be maskable`);
    }
  }
}

function assertStaticAssets() {
  const faviconPath = path.join(PUBLIC_DIR, "favicon.ico");
  if (!existsSync(faviconPath)) fail("public/favicon.ico is missing");
  const favicon = readFileSync(faviconPath);
  if (favicon.length < 6 || favicon.readUInt16LE(0) !== 0 || favicon.readUInt16LE(2) !== 1) {
    fail("public/favicon.ico is not a valid ICO file");
  }

  for (const icon of REQUIRED_ICONS) {
    const filePath = path.join(PUBLIC_DIR, icon.file);
    if (!existsSync(filePath)) fail(`public/${icon.file} is missing`);
    const dimensions = readPngDimensions(filePath);
    if (dimensions.width !== icon.width || dimensions.height !== icon.height) {
      fail(
        `public/${icon.file} must be ${icon.width}x${icon.height}, got ${dimensions.width}x${dimensions.height}`,
      );
    }
  }
}

function assertGeneratedServiceWorkerIfPresent() {
  const swPath = path.join(process.cwd(), ".output", "public", "sw.js");
  if (!existsSync(swPath)) return;

  const source = readFileSync(swPath, "utf8");
  const forbiddenPatterns = [
    /https?:\/\//i,
    /supabase/i,
    /\/auth\/v1/i,
    /\/rest\/v1/i,
    /\/rpc\//i,
    /\bfetch\s*\(/i,
    /\bregisterRoute\s*\(/i,
    /\bNetworkFirst\b/i,
    /\bStaleWhileRevalidate\b/i,
    /\bCacheFirst\b/i,
  ];

  for (const pattern of forbiddenPatterns) {
    if (pattern.test(source)) {
      fail(`generated service worker contains forbidden runtime cache/network pattern ${pattern}`);
    }
  }
}

assertManifest(readManifest());
assertStaticAssets();
assertGeneratedServiceWorkerIfPresent();
