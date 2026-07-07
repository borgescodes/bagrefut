/**
 * BagreFut minimal service worker.
 *
 * Foundation only:
 *  - no offline caching yet
 *  - no navigation fallback
 *  - registers push listeners so the Push API surface exists
 *
 * Real push delivery infrastructure (VAPID keys, backend sender) is pending.
 */

self.addEventListener("install", () => {
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener("push", (event) => {
  let payload = { title: "BagreFut", body: "Nova notificação" };
  try {
    if (event.data) payload = { ...payload, ...event.data.json() };
  } catch {
    /* body may not be JSON; keep defaults */
  }
  event.waitUntil(
    self.registration.showNotification(payload.title, {
      body: payload.body,
      icon: "/badges/badge-01.png",
      badge: "/badges/badge-01.png",
    }),
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  event.waitUntil(self.clients.openWindow("/"));
});
