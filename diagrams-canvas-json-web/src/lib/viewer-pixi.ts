import { Application, Container, RenderTexture, Sprite } from "pixi.js";
import type { BBox, CanvasCommand } from "./types.js";
import type { CommandLayer, CustomLayer } from "./viewer.js";
import {
  executeCommandsPixi,
  rgbaToHex,
  toMaskCommands,
} from "./renderer-pixi.js";

/** Options for creating a PixiJS pan-zoom viewer */
export interface PixiViewerOptions {
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
   * Custom Canvas 2D overlay layers rendered on top of the PixiJS content.
   * Each layer's render callback receives a 2D context with the same
   * pan/zoom transform applied, so drawing happens in diagram/gerber space.
   */
  customLayers?: CustomLayer[];
}

/** Handle returned by createPixiViewer for controlling the viewer */
export interface PixiViewer {
  /** Force a re-render */
  render(): void;

  /** Reset the view to fit the diagram in the viewport */
  fitToViewport(): void;

  /** Clean up event listeners, PixiJS app, and DOM elements */
  destroy(): void;

  /** Update the command layers and re-render */
  setCommandLayers(layers: CommandLayer[]): void;

  /** Update the custom Canvas 2D overlay layers and re-render */
  setCustomLayers(layers: CustomLayer[]): void;

  /** Get the current view transform state */
  getTransform(): { scale: number; tx: number; ty: number };

  /** Set the view transform state and re-render */
  setTransform(scale: number, tx: number, ty: number): void;
}

const DEFAULT_CHECKERBOARD =
  "conic-gradient(#d5d0e6 90deg, #cde0f0 90deg 180deg, #d5d0e6 180deg 270deg, #cde0f0 270deg) 0 0 / 20px 20px";

/** Per-layer rendering state */
interface LayerState {
  /** Scene container with mask commands, re-used across renders */
  scene: Container;
  /** RenderTexture at viewport pixel size */
  renderTexture: RenderTexture;
  /** Sprite on main stage displaying the tinted RT */
  sprite: Sprite;
  /** Whether this layer has destination-in commands (needs clip mask) */
  hasClip: boolean;
  /** Clip scene for destination-in content (only if hasClip) */
  clipScene?: Container;
  /** Clip RT (only if hasClip) */
  clipTexture?: RenderTexture;
  /** Clip sprite used as mask (only if hasClip) */
  clipSprite?: Sprite;
}

/**
 * Check if commands contain a GCO destination-in and split at the boundary.
 * Returns { content, clip } where clip is the commands inside the destination-in group.
 * If no destination-in, clip is empty.
 */
function splitAtDestinationIn(commands: CanvasCommand[]): {
  content: CanvasCommand[];
  clip: CanvasCommand[];
} {
  // Find the S/R group that starts with GCO destination-in.
  // Pattern: S, GCO destination-in, ...shapes..., R
  let clipStart = -1;
  let clipEnd = -1;
  let depth = 0;
  let clipStartDepth = -1;

  for (let i = 0; i < commands.length; i++) {
    const cmd = commands[i];
    if (cmd[0] === "S") {
      if (
        clipStart < 0 &&
        i + 1 < commands.length &&
        commands[i + 1][0] === "GCO" &&
        commands[i + 1][1] === "destination-in"
      ) {
        clipStart = i;
        clipStartDepth = depth;
      }
      depth++;
    } else if (cmd[0] === "R") {
      depth--;
      if (clipStart >= 0 && clipEnd < 0 && depth === clipStartDepth) {
        clipEnd = i;
      }
    }
  }

  if (clipStart < 0 || clipEnd < 0) {
    return { content: commands, clip: [] };
  }

  // Content: everything except the clip group
  const content = [
    ...commands.slice(0, clipStart),
    ...commands.slice(clipEnd + 1),
  ];
  // Clip: the shapes inside the clip group (skip S, GCO destination-in at start, and R at end)
  const clip = commands.slice(clipStart + 2, clipEnd);

  return { content, clip };
}

function buildLayerState(
  app: Application,
  layer: CommandLayer,
  width: number,
  height: number,
  resolution: number,
  scale: number,
): LayerState {
  const maskCmds = toMaskCommands(layer.commands);
  const { content, clip } = splitAtDestinationIn(maskCmds);
  const hasClip = clip.length > 0;

  // Build content scene
  const scene = new Container();
  executeCommandsPixi(scene, content, scale);

  // Create RT and sprite (resolution handles physical pixel scaling)
  const renderTexture = RenderTexture.create({ width, height, resolution });
  const sprite = new Sprite(renderTexture);
  const [r, g, b, a] = layer.color;
  sprite.tint = rgbaToHex(r, g, b);
  sprite.alpha = a;
  app.stage.addChild(sprite);

  let clipScene: Container | undefined;
  let clipTexture: RenderTexture | undefined;
  let clipSprite: Sprite | undefined;

  if (hasClip) {
    clipScene = new Container();
    executeCommandsPixi(clipScene, clip, scale);
    clipTexture = RenderTexture.create({ width, height, resolution });
    clipSprite = new Sprite(clipTexture);
    // Use clip sprite as mask on the content sprite
    sprite.mask = clipSprite;
    // clipSprite must be added to the stage for masking to work
    app.stage.addChild(clipSprite);
  }

  return {
    scene,
    renderTexture,
    sprite,
    hasClip,
    clipScene,
    clipTexture,
    clipSprite,
  };
}

function destroyLayerState(state: LayerState): void {
  state.scene.destroy({ children: true });
  state.renderTexture.destroy(true);
  state.sprite.destroy();
  if (state.clipScene) state.clipScene.destroy({ children: true });
  if (state.clipTexture) state.clipTexture.destroy(true);
  if (state.clipSprite) state.clipSprite.destroy();
}

/**
 * Create a PixiJS-based pan-zoom viewer inside a container element.
 *
 * Uses a mask-texture approach: each layer is rendered as white-on-transparent
 * to a RenderTexture, then displayed as a tinted Sprite. This correctly handles
 * gerber polarity compositing (destination-out for holes, destination-in for clipping).
 *
 * Performance: RenderTextures are only re-rendered when interaction stops (debounced).
 * During pan/zoom, sprites are repositioned/rescaled for instant feedback.
 */
export async function createPixiViewer(
  options: PixiViewerOptions,
): Promise<PixiViewer> {
  const { container, bounds, padding = 0.9 } = options;

  let commandLayers = options.commandLayers ?? [];
  let customLayers = options.customLayers ?? [];

  // Apply background
  if (options.background !== null) {
    container.style.background = options.background ?? DEFAULT_CHECKERBOARD;
  }

  // Ensure container is positioned for the PixiJS canvas
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

  // View transform state (current desired view)
  let scale = 1;
  let tx = 0;
  let ty = 0;

  // Drag state
  let dragging = false;
  let lastX = 0;
  let lastY = 0;

  // Initialize PixiJS Application
  const pr = window.devicePixelRatio || 1;
  const w = container.clientWidth;
  const h = container.clientHeight;
  const app = new Application();
  await app.init({
    width: w,
    height: h,
    resolution: pr,
    autoDensity: true,
    antialias: true,
    backgroundAlpha: 0,
  });
  container.appendChild(app.canvas);

  // Style the pixi canvas to fill container
  app.canvas.style.position = "absolute";
  app.canvas.style.top = "0";
  app.canvas.style.left = "0";
  app.canvas.style.width = "100%";
  app.canvas.style.height = "100%";
  app.canvas.style.pointerEvents = "none";

  // Transparent Canvas 2D overlay for custom layers (on top of PixiJS)
  const overlayCanvas = document.createElement("canvas");
  overlayCanvas.style.position = "absolute";
  overlayCanvas.style.top = "0";
  overlayCanvas.style.left = "0";
  overlayCanvas.style.width = "100%";
  overlayCanvas.style.height = "100%";
  overlayCanvas.style.pointerEvents = "none";
  container.appendChild(overlayCanvas);

  // Layer state
  let layerStates: LayerState[] = [];

  function fitToViewport(): void {
    const cw = container.clientWidth;
    const ch = container.clientHeight;
    scale =
      dw > 0 && dh > 0
        ? Math.min((cw * padding) / dw, (ch * padding) / dh)
        : 100;
    tx = cw / 2 - dcx * scale;
    ty = ch / 2 + dcy * scale;
  }

  function rebuildLayers(): void {
    // Destroy old layer states
    for (const ls of layerStates) {
      destroyLayerState(ls);
    }
    app.stage.removeChildren();

    const cw = container.clientWidth;
    const ch = container.clientHeight;

    layerStates = commandLayers.map((layer) =>
      buildLayerState(app, layer, cw, ch, pr, scale),
    );
  }

  /** Render all layer scenes to their RenderTextures at the current transform. */
  function renderFull(): void {
    const cw = container.clientWidth;
    const ch = container.clientHeight;

    // Resize app if needed
    if (
      app.renderer.width !== Math.round(cw * pr) ||
      app.renderer.height !== Math.round(ch * pr)
    ) {
      app.renderer.resize(cw, ch);
      for (const ls of layerStates) {
        ls.renderTexture.resize(cw, ch, pr);
        ls.sprite.texture = ls.renderTexture;
        if (ls.clipTexture) {
          ls.clipTexture.resize(cw, ch, pr);
          if (ls.clipSprite) ls.clipSprite.texture = ls.clipTexture;
        }
      }
    }

    // Apply pan/zoom transform in CSS pixel space
    function applyViewTransform(c: Container): void {
      c.position.set(tx, ty);
      c.scale.set(scale, -scale);
    }

    for (const ls of layerStates) {
      applyViewTransform(ls.scene);
      app.renderer.render({
        container: ls.scene,
        target: ls.renderTexture,
        clear: true,
        clearColor: [0, 0, 0, 0],
      });

      if (ls.hasClip && ls.clipScene && ls.clipTexture) {
        applyViewTransform(ls.clipScene);
        app.renderer.render({
          container: ls.clipScene,
          target: ls.clipTexture,
          clear: true,
          clearColor: [0, 0, 0, 0],
        });
      }
    }

    app.render();

    // Render custom Canvas 2D overlay layers
    const ow = container.clientWidth;
    const oh = container.clientHeight;
    overlayCanvas.width = Math.round(ow * pr);
    overlayCanvas.height = Math.round(oh * pr);
    overlayCanvas.style.width = ow + "px";
    overlayCanvas.style.height = oh + "px";
    const octx = overlayCanvas.getContext("2d")!;
    octx.setTransform(pr, 0, 0, pr, 0, 0);
    octx.clearRect(0, 0, ow, oh);
    for (const cl of customLayers) {
      octx.save();
      octx.transform(scale, 0, 0, -scale, tx, ty);
      cl.render(octx, scale);
      octx.restore();
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
    renderFull();
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
    renderFull();
  }

  function onMouseUp(): void {
    dragging = false;
    container.style.cursor = "grab";
  }

  function onResize(): void {
    fitToViewport();
    renderFull();
  }

  // Attach event listeners
  container.addEventListener("wheel", onWheel, { passive: false });
  container.addEventListener("mousedown", onMouseDown);
  window.addEventListener("mousemove", onMouseMove);
  window.addEventListener("mouseup", onMouseUp);
  window.addEventListener("resize", onResize);

  // Initial fit and render
  fitToViewport();
  rebuildLayers();
  renderFull();

  return {
    render: renderFull,
    fitToViewport() {
      fitToViewport();
      renderFull();
    },

    destroy(): void {
      container.removeEventListener("wheel", onWheel);
      container.removeEventListener("mousedown", onMouseDown);
      window.removeEventListener("mousemove", onMouseMove);
      window.removeEventListener("mouseup", onMouseUp);
      window.removeEventListener("resize", onResize);
      for (const ls of layerStates) {
        destroyLayerState(ls);
      }
      layerStates = [];
      app.destroy(true);
      overlayCanvas.remove();
    },

    setCommandLayers(layers: CommandLayer[]): void {
      commandLayers = layers;
      rebuildLayers();
      renderFull();
    },

    setCustomLayers(layers: CustomLayer[]): void {
      customLayers = layers;
      renderFull();
    },

    getTransform() {
      return { scale, tx, ty };
    },

    setTransform(s: number, x: number, y: number): void {
      scale = s;
      tx = x;
      ty = y;
      renderFull();
    },
  };
}
