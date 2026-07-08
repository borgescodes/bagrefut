// @lovable.dev/vite-tanstack-config already includes the following — do NOT add them manually
// or the app will break with duplicate plugins:
//   - tanstackStart, viteReact, tailwindcss, tsConfigPaths, nitro (build-only using cloudflare as a default target),
//     componentTagger (dev-only), VITE_* env injection, @ path alias, React/TanStack dedupe,
//     error logger plugins, and sandbox detection (port/host/strictPort).
// You can pass additional config via defineConfig({ vite: { ... }, etc... }) if needed.
import { defineConfig } from "@lovable.dev/vite-tanstack-config";
import { VitePWA } from "vite-plugin-pwa";

export default defineConfig({
  plugins: [
    VitePWA({
      registerType: "autoUpdate",
      injectRegister: false,
      manifest: false,
      outDir: ".output/public",
      includeAssets: ["favicon.ico", "apple-touch-icon.png"],
      workbox: {
        globPatterns: ["**/*.{js,css,html,ico,png,svg,webmanifest}"],
        navigateFallback: undefined,
        runtimeCaching: [],
      },
    }),
  ],
  tanstackStart: {
    // Redirect TanStack Start's bundled server entry to src/server.ts (our SSR error wrapper).
    // nitro/vite builds from this
    server: { entry: "server" },
  },
  vite: {
    environments: {
      client: {
        build: {
          rolldownOptions: {
            output: {
              codeSplitting: {
                groups: [
                  {
                    name: "react",
                    test: /node_modules[\\/](react|react-dom)[\\/]/,
                    priority: 40,
                  },
                  {
                    name: "tanstack",
                    test: /node_modules[\\/]@tanstack[\\/]/,
                    priority: 30,
                  },
                  {
                    name: "supabase",
                    test: /node_modules[\\/]@supabase[\\/]/,
                    priority: 20,
                  },
                  {
                    name: "radix",
                    test: /node_modules[\\/]@radix-ui[\\/]/,
                    priority: 10,
                  },
                  {
                    name: "vendor",
                    test: /node_modules[\\/]/,
                  },
                ],
              },
            },
          },
        },
      },
    },
  },
});
