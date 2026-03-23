import type { BBox, CanvasCommand } from "./types.js";
import { executeCommands } from "./renderer.js";

/** A layer with pre-colored canvas commands */
export interface CommandLayer {
  name?: string;
  color: [number, number, number, number];
  commands: CanvasCommand[];
}

/** Multi-layer diagram structure from the backend */
export interface LayeredDiagram {
  width: number;
  height: number;
  bounds: BBox;
  layers: CommandLayer[];
}

/**
 * Callback for rendering a custom canvas layer.
 * Called during each render pass with the canvas context already set up
 * with the current pan/zoom transform (scale, 0, 0, -scale, tx, ty).
 *
 * @param ctx - The 2D rendering context with pan/zoom transform applied
 * @param scale - Current zoom scale (useful for adjusting line widths)
 */
export type CustomLayerRenderer = (
  ctx: CanvasRenderingContext2D,
  scale: number,
) => void;

/** Configuration for a custom canvas layer */
export interface CustomLayer {
  /** Render callback invoked each frame */
  render: CustomLayerRenderer;
}

/** Options for creating a pan-zoom viewer */
export interface ViewerOptions {
  /** Container element that the viewer will fill */
  container: HTMLElement;

  /** Diagram bounds for computing the fit transform */
  bounds: BBox;

  /**
   * Background CSS value for the container.
   * Defaults to a checkerboard pattern that shows transparency.
   * Set to a color string like '#ffffff' for a solid background,
   * or null to inherit the container's existing background.
   */
  background?: string | null;

  /** Padding factor for fitting diagram (0-1, default: 0.9 = 10% padding) */
  padding?: number;

  /** Canvas command layers to render (bottom to top) */
  commandLayers?: CommandLayer[];

  /**
   * Custom canvas layers rendered after command layers.
   * Each custom layer gets its own stacked canvas with the same
   * pan/zoom transform applied.
   */
  customLayers?: CustomLayer[];
}

/** Handle returned by createViewer for controlling the viewer */
export interface Viewer {
  /** Force a re-render */
  render(): void;

  /** Reset the view to fit the diagram in the viewport */
  fitToViewport(): void;

  /** Clean up event listeners and DOM elements */
  destroy(): void;

  /** Update the command layers and re-render */
  setCommandLayers(layers: CommandLayer[]): void;

  /** Update the custom layers and re-render */
  setCustomLayers(layers: CustomLayer[]): void;

  /** Get the current view transform state */
  getTransform(): { scale: number; tx: number; ty: number };

  /** Set the view transform state and re-render */
  setTransform(scale: number, tx: number, ty: number): void;
}

const DEFAULT_CHECKERBOARD =
  "conic-gradient(#d5d0e6 90deg, #cde0f0 90deg 180deg, #d5d0e6 180deg 270deg, #cde0f0 270deg) 0 0 / 20px 20px";

/**
 * Create a pan-zoom viewer inside a container element.
 *
 * The viewer creates stacked canvas elements for each command layer
 * and custom layer, all sharing the same pan/zoom transform. Mouse
 * wheel zooms anchored at the cursor, and mouse drag pans the view.
 *
 * @example
 * ```ts
 * // Basic usage with a multi-layer diagram
 * const viewer = createViewer({
 *   container: document.getElementById('viewer')!,
 *   bounds: diagram.bounds,
 *   commandLayers: diagram.layers,
 * });
 *
 * // With custom overlay layer
 * const viewer = createViewer({
 *   container: document.getElementById('viewer')!,
 *   bounds: diagram.bounds,
 *   commandLayers: diagram.layers,
 *   background: '#2a2a2a',
 *   customLayers: [{
 *     render: (ctx, scale) => {
 *       ctx.beginPath();
 *       ctx.arc(0, 0, 5, 0, Math.PI * 2);
 *       ctx.fillStyle = 'red';
 *       ctx.fill();
 *     }
 *   }],
 * });
 * ```
 */
export function createViewer(options: ViewerOptions): Viewer {
  const { container, bounds, padding = 0.9 } = options;

  let commandLayers = options.commandLayers ?? [];
  let customLayers = options.customLayers ?? [];

  // Apply background
  if (options.background !== null) {
    container.style.background = options.background ?? DEFAULT_CHECKERBOARD;
  }

  // Ensure container is positioned for absolute canvas children
  const pos = getComputedStyle(container).position;
  if (pos === "static") {
    container.style.position = "relative";
  }
  container.style.overflow = "hidden";
  container.style.cursor = "grab";

  // Diagram bounds center and size
  const dcx = (bounds.minX + bounds.maxX) / 2;
  const dcy = (bounds.minY + bounds.maxY) / 2;
  const dw = bounds.maxX - bounds.minX;
  const dh = bounds.maxY - bounds.minY;

  // View transform state
  let scale = 1;
  let tx = 0;
  let ty = 0;

  // Drag state
  let dragging = false;
  let lastX = 0;
  let lastY = 0;

  // Canvas pool: we create/remove canvases as layers change
  let canvases: HTMLCanvasElement[] = [];

  function ensureCanvasCount(count: number): void {
    while (canvases.length < count) {
      const c = document.createElement("canvas");
      c.style.position = "absolute";
      c.style.top = "0";
      c.style.left = "0";
      c.style.pointerEvents = "none";
      container.appendChild(c);
      canvases.push(c);
    }
    while (canvases.length > count) {
      const c = canvases.pop()!;
      container.removeChild(c);
    }
  }

  function fitToViewport(): void {
    const w = container.clientWidth;
    const h = container.clientHeight;
    scale =
      dw > 0 && dh > 0 ? Math.min((w * padding) / dw, (h * padding) / dh) : 100;
    tx = w / 2 - dcx * scale;
    ty = h / 2 + dcy * scale;
  }

  function render(): void {
    const pr = window.devicePixelRatio || 1;
    const w = container.clientWidth;
    const h = container.clientHeight;
    const pw = w * pr;
    const ph = h * pr;

    const totalLayers = commandLayers.length + customLayers.length;
    ensureCanvasCount(totalLayers);

    // Render command layers
    for (let i = 0; i < commandLayers.length; i++) {
      const c = canvases[i];
      c.width = pw;
      c.height = ph;
      c.style.width = w + "px";
      c.style.height = h + "px";
      const ctx = c.getContext("2d")!;
      ctx.setTransform(pr, 0, 0, pr, 0, 0);
      ctx.clearRect(0, 0, w, h);
      ctx.save();
      ctx.transform(scale, 0, 0, -scale, tx, ty);
      executeCommands(ctx, commandLayers[i].commands, scale);
      ctx.restore();
    }

    // Render custom layers
    for (let i = 0; i < customLayers.length; i++) {
      const canvasIdx = commandLayers.length + i;
      const c = canvases[canvasIdx];
      c.width = pw;
      c.height = ph;
      c.style.width = w + "px";
      c.style.height = h + "px";
      const ctx = c.getContext("2d")!;
      ctx.setTransform(pr, 0, 0, pr, 0, 0);
      ctx.clearRect(0, 0, w, h);
      ctx.save();
      ctx.transform(scale, 0, 0, -scale, tx, ty);
      customLayers[i].render(ctx, scale);
      ctx.restore();
    }
  }

  // Zoom on scroll, anchored at mouse position
  function onWheel(e: WheelEvent): void {
    e.preventDefault();
    const rect = container.getBoundingClientRect();
    const mx = e.clientX - rect.left;
    const my = e.clientY - rect.top;
    const factor = e.deltaY < 0 ? 1.15 : 1 / 1.15;
    const newScale = scale * factor;
    tx = mx - (mx - tx) * (newScale / scale);
    ty = my - (my - ty) * (newScale / scale);
    scale = newScale;
    render();
  }

  function onMouseDown(e: MouseEvent): void {
    dragging = true;
    lastX = e.clientX;
    lastY = e.clientY;
    container.style.cursor = "grabbing";
  }

  function onMouseMove(e: MouseEvent): void {
    if (!dragging) return;
    tx += e.clientX - lastX;
    ty += e.clientY - lastY;
    lastX = e.clientX;
    lastY = e.clientY;
    render();
  }

  function onMouseUp(): void {
    dragging = false;
    container.style.cursor = "grab";
  }

  function onResize(): void {
    fitToViewport();
    render();
  }

  // Attach event listeners
  container.addEventListener("wheel", onWheel, { passive: false });
  container.addEventListener("mousedown", onMouseDown);
  window.addEventListener("mousemove", onMouseMove);
  window.addEventListener("mouseup", onMouseUp);
  window.addEventListener("resize", onResize);

  // Initial fit and render
  fitToViewport();
  render();

  return {
    render,
    fitToViewport,

    destroy(): void {
      container.removeEventListener("wheel", onWheel);
      container.removeEventListener("mousedown", onMouseDown);
      window.removeEventListener("mousemove", onMouseMove);
      window.removeEventListener("mouseup", onMouseUp);
      window.removeEventListener("resize", onResize);
      for (const c of canvases) {
        container.removeChild(c);
      }
      canvases = [];
    },

    setCommandLayers(layers: CommandLayer[]): void {
      commandLayers = layers;
      render();
    },

    setCustomLayers(layers: CustomLayer[]): void {
      customLayers = layers;
      render();
    },

    getTransform() {
      return { scale, tx, ty };
    },

    setTransform(s: number, x: number, y: number): void {
      scale = s;
      tx = x;
      ty = y;
      render();
    },
  };
}
