/**
 * Registers the BagreFut service worker in production only.
 * Explicitly skips Lovable preview / dev / iframe environments to avoid
 * stale-cache issues in the editor preview.
 */
export function registerServiceWorker(): void {
  if (typeof window === "undefined") return;
  if (!("serviceWorker" in navigator)) return;

  // Skip in dev/preview
  const host = window.location.hostname;
  const isPreview =
    host.startsWith("id-preview--") ||
    host.startsWith("preview--") ||
    host === "lovableproject.com" ||
    host.endsWith(".lovableproject.com") ||
    host.endsWith(".lovableproject-dev.com") ||
    host === "beta.lovable.dev" ||
    host.endsWith(".beta.lovable.dev");
  const isIframe = window.self !== window.top;
  const disabled = new URL(window.location.href).searchParams.get("sw") === "off";
  const isProd = import.meta.env.PROD;

  if (!isProd || isPreview || isIframe || disabled) {
    // Best-effort cleanup of any stale registration
    void navigator.serviceWorker.getRegistrations().then((regs) => {
      for (const r of regs) if (r.active?.scriptURL.endsWith("/sw.js")) r.unregister();
    });
    return;
  }

  window.addEventListener("load", () => {
    void navigator.serviceWorker.register("/sw.js", { scope: "/" }).catch((error) => {
      console.warn("[BagreFut] service worker registration failed", error);
    });
  });
}
