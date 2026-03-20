/**
 * PixiJS rendering backend for diagrams-canvas-json-web
 *
 * Import from "diagrams-canvas-json-web/pixi" to use the PixiJS renderer.
 * Requires pixi.js as a dependency.
 */

export type { CanvasDiagram, CanvasCommand, Color, BBox } from "./types.js";
export {
  executeCommandsPixi,
  renderDiagramPixi,
  createPixiApp,
} from "./renderer-pixi.js";
export type { RenderPixiOptions } from "./renderer-pixi.js";
