import { defineConfig } from "vite";
import { resolve } from "path";

export default defineConfig({
  build: {
    lib: {
      entry: resolve(__dirname, "src/lib/pixi.ts"),
      name: "DiagramsCanvasJsonPixi",
      fileName: "diagrams-canvas-json-web-pixi",
      formats: ["iife"],
    },
    outDir: "dist",
    emptyOutDir: false,
  },
});
