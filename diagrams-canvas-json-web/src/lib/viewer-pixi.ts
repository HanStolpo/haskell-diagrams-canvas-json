import {
  Application,
  Container,
  RenderTexture,
  Sprite,
  Texture,
} from "pixi.js";
import type { BBox, CanvasCommand } from "./types.js";
import type { ViewerLayer } from "./viewer.js";
import { isMaskLayer, isCustomLayer } from "./viewer.js";
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

  /** Layers to render (bottom to top), command and custom layers interleaved */
  layers?: ViewerLayer[];
}

/** Handle returned by createPixiViewer for controlling the viewer */
export interface PixiViewer {
  /** Force a re-render */
  render(): void;

  /** Reset the view to fit the diagram in the viewport */
  fitToViewport(): void;

  /** Clean up event listeners, PixiJS app, and DOM elements */
  destroy(): void;

  /** Update the layers and re-render */
  setLayers(layers: ViewerLayer[]): void;

  /** Get the current view transform state */
  getTransform(): { scale: number; tx: number; ty: number };

  /** Set the view transform state and re-render */
  setTransform(scale: number, tx: number, ty: number): void;
}

const DEFAULT_CHECKERBOARD =
  "conic-gradient(#d5d0e6 90deg, #cde0f0 90deg 180deg, #d5d0e6 180deg 270deg, #cde0f0 270deg) 0 0 / 20px 20px";

/** Per-command-layer rendering state (renders commands directly to RT) */
interface CommandLayerState {
  kind: "command";
  scene: Container;
  renderTexture: RenderTexture;
  sprite: Sprite;
}

/** Per-mask-layer rendering state (white-on-transparent mask, tinted sprite) */
interface MaskLayerState {
  kind: "mask";
  scene: Container;
  renderTexture: RenderTexture;
  sprite: Sprite;
  /** Whether this layer has destination-in commands (needs clip mask) */
  hasClip: boolean;
  clipScene?: Container;
  clipTexture?: RenderTexture;
  clipSprite?: Sprite;
}

/** Per-custom-layer rendering state */
interface CustomLayerState {
  kind: "custom";
  canvas: HTMLCanvasElement;
  sprite: Sprite;
  render: (ctx: CanvasRenderingContext2D, scale: number) => void;
}

type LayerState = CommandLayerState | MaskLayerState | CustomLayerState;

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

function buildCommandLayerState(
  app: Application,
  commands: CanvasCommand[],
  width: number,
  height: number,
  resolution: number,
  scale: number,
): CommandLayerState {
  const scene = new Container();
  executeCommandsPixi(scene, commands, scale);
  const renderTexture = RenderTexture.create({ width, height, resolution });
  const sprite = new Sprite(renderTexture);
  app.stage.addChild(sprite);
  return { kind: "command", scene, renderTexture, sprite };
}

function buildMaskLayerState(
  app: Application,
  color: [number, number, number, number],
  commands: CanvasCommand[],
  width: number,
  height: number,
  resolution: number,
  scale: number,
): MaskLayerState {
  const maskCmds = toMaskCommands(commands);
  const { content, clip } = splitAtDestinationIn(maskCmds);
  const hasClip = clip.length > 0;

  const scene = new Container();
  executeCommandsPixi(scene, content, scale);

  const renderTexture = RenderTexture.create({ width, height, resolution });
  const sprite = new Sprite(renderTexture);
  const [r, g, b, a] = color;
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
    sprite.mask = clipSprite;
    app.stage.addChild(clipSprite);
  }

  return {
    kind: "mask",
    scene,
    renderTexture,
    sprite,
    hasClip,
    clipScene,
    clipTexture,
    clipSprite,
  };
}

function buildCustomLayerState(
  app: Application,
  render: (ctx: CanvasRenderingContext2D, scale: number) => void,
  width: number,
  height: number,
): CustomLayerState {
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const sprite = new Sprite(Texture.from(canvas));
  app.stage.addChild(sprite);
  return { kind: "custom", canvas, sprite, render };
}

function destroyLayerState(state: LayerState): void {
  if (state.kind === "command") {
    state.scene.destroy({ children: true });
    state.renderTexture.destroy(true);
    state.sprite.destroy();
  } else if (state.kind === "mask") {
    state.scene.destroy({ children: true });
    state.renderTexture.destroy(true);
    state.sprite.destroy();
    if (state.clipScene) state.clipScene.destroy({ children: true });
    if (state.clipTexture) state.clipTexture.destroy(true);
    if (state.clipSprite) state.clipSprite.destroy();
  } else {
    state.sprite.destroy();
  }
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

  let layers: ViewerLayer[] = options.layers ?? [];

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
    autoStart: false, // Don't start the ticker — we render manually via renderFull()
  });
  app.ticker.stop(); // Ensure ticker is stopped even if autoStart didn't take effect
  container.appendChild(app.canvas);

  // Style the pixi canvas to fill container
  app.canvas.style.position = "absolute";
  app.canvas.style.top = "0";
  app.canvas.style.left = "0";
  app.canvas.style.width = "100%";
  app.canvas.style.height = "100%";
  app.canvas.style.pointerEvents = "none";

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

    layerStates = layers.map((layer) => {
      if (isMaskLayer(layer)) {
        return buildMaskLayerState(
          app,
          layer.color,
          layer.commands,
          cw,
          ch,
          pr,
          scale,
        );
      } else if (isCustomLayer(layer)) {
        return buildCustomLayerState(app, layer.render, cw, ch);
      } else {
        return buildCommandLayerState(app, layer.commands, cw, ch, pr, scale);
      }
    });
  }

  let destroyed = false;

  /** Render all layer scenes to their RenderTextures at the current transform. */
  function renderFull(): void {
    if (destroyed) { return; }
    const cw = container.clientWidth;
    const ch = container.clientHeight;

    // Resize app if needed
    if (
      app.renderer.width !== Math.round(cw * pr) ||
      app.renderer.height !== Math.round(ch * pr)
    ) {
      app.renderer.resize(cw, ch);
      for (const ls of layerStates) {
        if (ls.kind === "command" || ls.kind === "mask") {
          ls.renderTexture.resize(cw, ch, pr);
          ls.sprite.texture = ls.renderTexture;
        }
        if (ls.kind === "mask" && ls.clipTexture) {
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

    const pw = Math.round(cw * pr);
    const ph = Math.round(ch * pr);

    for (let i = 0; i < layerStates.length; i++) {
      const ls = layerStates[i];
      const hidden = layers[i]?.visible === false;
      ls.sprite.visible = !hidden;
      if (ls.kind === "mask" && ls.clipSprite) {
        ls.clipSprite.visible = !hidden;
      }
      if (hidden) continue;

      if (ls.kind === "command") {
        applyViewTransform(ls.scene);
        app.renderer.render({
          container: ls.scene,
          target: ls.renderTexture,
          clear: true,
          clearColor: [0, 0, 0, 0],
        });
      } else if (ls.kind === "mask") {
        // Re-read color from the layer in case it was mutated
        const maskLayer = layers[i];
        if (maskLayer && isMaskLayer(maskLayer)) {
          const [r, g, b, a] = maskLayer.color;
          ls.sprite.tint = rgbaToHex(r, g, b);
          ls.sprite.alpha = a;
        }
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
      } else {
        // Render custom layer to offscreen canvas, upload as texture
        const canvas = ls.canvas;
        if (canvas.width !== pw || canvas.height !== ph) {
          canvas.width = pw;
          canvas.height = ph;
        }
        const ctx = canvas.getContext("2d")!;
        ctx.setTransform(pr, 0, 0, pr, 0, 0);
        ctx.clearRect(0, 0, cw, ch);
        ctx.save();
        ctx.transform(scale, 0, 0, -scale, tx, ty);
        ls.render(ctx, scale);
        ctx.restore();
        ls.sprite.texture.source.resource = canvas;
        ls.sprite.texture.source.resolution = pr;
        ls.sprite.texture.source.update();
      }
    }

    app.render();
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
      destroyed = true;
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
    },

    setLayers(newLayers: ViewerLayer[]): void {
      const needsRebuild =
        newLayers.length !== layers.length ||
        newLayers.some((l, i) => {
          const old = layers[i];
          if (isMaskLayer(l) !== isMaskLayer(old)) return true;
          if (isCustomLayer(l) !== isCustomLayer(old)) return true;
          // Mask layers: rebuild if commands changed (color changes are handled in renderFull)
          if (isMaskLayer(l) && isMaskLayer(old) && l.commands !== old.commands)
            return true;
          // Custom layers: render callback may have changed, no rebuild needed
          return false;
        });
      layers = newLayers;
      if (needsRebuild) {
        rebuildLayers();
      }
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
