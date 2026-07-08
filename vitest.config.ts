import { defineConfig } from "vitest/config";
import path from "node:path";

export default defineConfig({
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  test: {
    environment: "node",
    include: [
      "src/test/**/*.test.ts",
      "src/test/**/*.test.tsx",
      "src/test/**/*.spec.ts",
      "src/test/**/*.spec.tsx",
    ],
    globals: false,
    clearMocks: true,
    restoreMocks: true,
    mockReset: true,
    unstubEnvs: true,
    unstubGlobals: true,
    passWithNoTests: false,
    coverage: {
      provider: "v8",
      reporter: ["text", "json-summary", "html"],
      reportsDirectory: "coverage",
      exclude: [
        "coverage/**",
        "dist/**",
        ".output/**",
        ".vinxi/**",
        ".tanstack/**",
        "src/routeTree.gen.ts",
        "src/**/*.gen.ts",
        "src/integrations/supabase/types.ts",
        "**/*.d.ts",
        "vite.config.ts",
        "vitest.config.ts",
        "eslint.config.js",
        "src/test/**",
        "src/**/__fixtures__/**",
        "src/**/*.fixture.ts",
        "src/**/*.fixtures.ts",
      ],
    },
  },
});
