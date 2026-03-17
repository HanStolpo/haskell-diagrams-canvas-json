import { defineConfig } from "vite";
import { resolve } from "path";

export default defineConfig({
  build: {
    lib: {
      entry: resolve(__dirname, "src/lib/index.ts"),
      name: "DiagramsCanvasJson",
      fileName: "diagrams-canvas-json-web",
      formats: ["iife"],
    },
    outDir: "dist",
    emptyOutDir: false,
  },
});
