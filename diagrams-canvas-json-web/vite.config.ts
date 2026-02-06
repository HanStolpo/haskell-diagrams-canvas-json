import { defineConfig } from "vite";
import { resolve } from "path";

export default defineConfig({
  root: "dev",
  server: {
    port: 3000,
    proxy: {
      // Proxy requests to the Haskell server for diagram JSON data
      "/api": {
        target: "http://localhost:8080",
        changeOrigin: true,
      },
    },
  },
  resolve: {
    alias: {
      "diagrams-canvas-json-web": resolve(__dirname, "src/lib"),
    },
  },
  build: {
    outDir: "../dist-dev",
    emptyOutDir: true,
  },
});
