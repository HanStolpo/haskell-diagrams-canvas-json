import {
  Application,
  Container,
  Graphics,
  GraphicsContextSystem,
  Matrix,
  Text,
} from "pixi.js";
import type { CanvasDiagram, CanvasCommand, Color, BBox } from "./types.js";
import { calculateFitTransform } from "./renderer.js";

/** A buffered path operation to replay into Graphics */
interface PathOp {
  type:
    | "moveTo"
    | "lineTo"
    | "bezierCurveTo"
    | "quadraticCurveTo"
    | "arc"
    | "closePath";
  args: number[];
}

/** Drawing state tracked manually (Canvas 2D has this built-in) */
interface DrawState {
  fillColor: { r: number; g: number; b: number; a: number };
  strokeColor: { r: number; g: number; b: number; a: number };
  lineWidth: number;
  lineWidthViewRelative: boolean;
  lineCap: "butt" | "round" | "square";
  lineJoin: "miter" | "round" | "bevel";
  font: string;
  blendMode: string;
}

function cloneState(s: DrawState): DrawState {
  return {
    fillColor: { ...s.fillColor },
    strokeColor: { ...s.strokeColor },
    lineWidth: s.lineWidth,
    lineWidthViewRelative: s.lineWidthViewRelative,
    lineCap: s.lineCap,
    lineJoin: s.lineJoin,
    font: s.font,
    blendMode: s.blendMode,
  };
}

function defaultState(): DrawState {
  return {
    fillColor: { r: 0, g: 0, b: 0, a: 1 },
    strokeColor: { r: 0, g: 0, b: 0, a: 1 },
    lineWidth: 1,
    lineWidthViewRelative: false,
    lineCap: "butt",
    lineJoin: "miter",
    font: "10px sans-serif",
    blendMode: "normal",
  };
}

/** Convert RGBA (0-255 for RGB) to a hex number for PixiJS */
function rgbaToHex(r: number, g: number, b: number): number {
  return (
    ((Math.round(r) & 0xff) << 16) |
    ((Math.round(g) & 0xff) << 8) |
    (Math.round(b) & 0xff)
  );
}

/** Convert line cap number to string */
function lineCapToString(cap: number): "butt" | "round" | "square" {
  switch (cap) {
    case 1:
      return "round";
    case 2:
      return "square";
    default:
      return "butt";
  }
}

/** Convert line join number to string */
function lineJoinToString(join: number): "miter" | "round" | "bevel" {
  switch (join) {
    case 1:
      return "round";
    case 2:
      return "bevel";
    default:
      return "miter";
  }
}

/** Map Canvas 2D globalCompositeOperation to PixiJS blend mode string */
function compositeOpToBlendMode(op: string): string {
  const map: Record<string, string> = {
    "source-over": "normal",
    multiply: "multiply",
    screen: "screen",
    overlay: "overlay",
    darken: "darken",
    lighten: "lighten",
    "color-dodge": "color-dodge",
    "color-burn": "color-burn",
    "hard-light": "hard-light",
    "soft-light": "soft-light",
    difference: "difference",
    exclusion: "exclusion",
    "destination-out": "erase",
  };
  const result = map[op];
  if (!result) {
    console.warn(
      `Unsupported composite operation "${op}", falling back to normal`,
    );
    return "normal";
  }
  return result;
}

/**
 * Approximate a circular arc with cubic bezier curves.
 * Splits the arc into segments of at most PI/2 and uses the standard
 * cubic bezier approximation for each segment.
 *
 * Like Canvas 2D arc(), this first adds a lineTo from the current point
 * to the arc start, then emits bezier segments for the arc itself.
 */
function replayArc(
  g: Graphics,
  cx: number,
  cy: number,
  r: number,
  startAngle: number,
  endAngle: number,
): void {
  const sweep = endAngle - startAngle;
  if (sweep === 0) return;

  const absSweep = Math.abs(sweep);

  // Split into segments of at most PI/2
  const segCount = Math.ceil(absSweep / (Math.PI / 2));
  const segSweep = sweep / segCount;

  // Move to arc start
  const sx = cx + r * Math.cos(startAngle);
  const sy = cy + r * Math.sin(startAngle);
  g.moveTo(sx, sy);

  // For each segment, compute the cubic bezier control points
  // Using the standard approximation: alpha = (4/3) * tan(sweep/4)
  for (let i = 0; i < segCount; i++) {
    const a1 = startAngle + i * segSweep;
    const a2 = a1 + segSweep;
    const alpha = (4 / 3) * Math.tan(segSweep / 4);

    const cos1 = Math.cos(a1);
    const sin1 = Math.sin(a1);
    const cos2 = Math.cos(a2);
    const sin2 = Math.sin(a2);

    const cp1x = cx + r * (cos1 - alpha * sin1);
    const cp1y = cy + r * (sin1 + alpha * cos1);
    const cp2x = cx + r * (cos2 + alpha * sin2);
    const cp2y = cy + r * (sin2 - alpha * cos2);
    const ex = cx + r * cos2;
    const ey = cy + r * sin2;

    g.bezierCurveTo(cp1x, cp1y, cp2x, cp2y, ex, ey, 0.99);
  }
}

/**
 * Replay buffered path operations onto a Graphics object.
 * Bezier/quadratic curves use smoothness=0.99 to ensure fine tessellation
 * even when diagram-space coordinates are small (e.g. radius ~1).
 */
function replayPath(g: Graphics, buffer: PathOp[]): void {
  for (const op of buffer) {
    switch (op.type) {
      case "moveTo":
        g.moveTo(op.args[0], op.args[1]);
        break;
      case "lineTo":
        g.lineTo(op.args[0], op.args[1]);
        break;
      case "bezierCurveTo":
        g.bezierCurveTo(
          op.args[0],
          op.args[1],
          op.args[2],
          op.args[3],
          op.args[4],
          op.args[5],
          0.99,
        );
        break;
      case "quadraticCurveTo":
        g.quadraticCurveTo(
          op.args[0],
          op.args[1],
          op.args[2],
          op.args[3],
          0.99,
        );
        break;
      case "arc":
        replayArc(
          g,
          op.args[0],
          op.args[1],
          op.args[2],
          op.args[3],
          op.args[4],
        );
        break;
      case "closePath":
        g.closePath();
        break;
    }
  }
}

/**
 * Execute a list of canvas commands, populating a PixiJS Container.
 * @param parent - The Container to add display objects to
 * @param commands - The command stream to interpret
 * @param scale - The current transform scale, used for view-relative line widths
 */
export function executeCommandsPixi(
  parent: Container,
  commands: CanvasCommand[],
  scale: number,
): void {
  let state = defaultState();
  const stateStack: { state: DrawState; container: Container }[] = [];
  let currentContainer = parent;
  let pathBuffer: PathOp[] = [];

  function doFill(r: number, g: number, b: number, a: number): void {
    if (pathBuffer.length === 0) return;
    const g2 = new Graphics();
    g2.context.beginPath();
    replayPath(g2, pathBuffer);
    g2.fill({ color: rgbaToHex(r, g, b), alpha: a });
    g2.blendMode = state.blendMode as never;
    currentContainer.addChild(g2);
  }

  function doStroke(
    r: number,
    g: number,
    b: number,
    a: number,
    lineWidth: number,
  ): void {
    if (pathBuffer.length === 0) return;
    const g2 = new Graphics();
    g2.context.beginPath();
    replayPath(g2, pathBuffer);
    g2.stroke({
      color: rgbaToHex(r, g, b),
      alpha: a,
      width: lineWidth,
      cap: state.lineCap,
      join: state.lineJoin,
    });
    g2.blendMode = state.blendMode as never;
    currentContainer.addChild(g2);
  }

  for (const cmd of commands) {
    const opcode = cmd[0];

    switch (opcode) {
      // State management
      case "S": {
        const child = new Container();
        currentContainer.addChild(child);
        stateStack.push({
          state: cloneState(state),
          container: currentContainer,
        });
        currentContainer = child;
        break;
      }
      case "R": {
        const entry = stateStack.pop();
        if (entry) {
          state = entry.state;
          currentContainer = entry.container;
        }
        break;
      }

      // Transform
      case "T": {
        const [, a, b, c, d, e, f] = cmd;
        const child = new Container();
        child.setFromMatrix(new Matrix(a, b, c, d, e, f));
        currentContainer.addChild(child);
        currentContainer = child;
        break;
      }

      // Path commands
      case "B":
        pathBuffer = [];
        break;
      case "M": {
        const [, x, y] = cmd;
        pathBuffer.push({ type: "moveTo", args: [x, y] });
        break;
      }
      case "L": {
        const [, x, y] = cmd;
        pathBuffer.push({ type: "lineTo", args: [x, y] });
        break;
      }
      case "C": {
        const [, cx1, cy1, cx2, cy2, x, y] = cmd;
        pathBuffer.push({
          type: "bezierCurveTo",
          args: [cx1, cy1, cx2, cy2, x, y],
        });
        break;
      }
      case "Q": {
        const [, cx, cy, x, y] = cmd;
        pathBuffer.push({ type: "quadraticCurveTo", args: [cx, cy, x, y] });
        break;
      }
      case "A": {
        const [, cx, cy, r, startAngle, endAngle] = cmd;
        pathBuffer.push({
          type: "arc",
          args: [cx, cy, r, startAngle, endAngle],
        });
        break;
      }
      case "Z":
        pathBuffer.push({ type: "closePath", args: [] });
        break;

      // Fill with color
      case "F": {
        const [, r, g, b, a] = cmd;
        doFill(r, g, b, a);
        break;
      }

      // Stroke (coordinate-space line width)
      case "K": {
        const [, r, g, b, a, lineWidth] = cmd;
        doStroke(r, g, b, a, lineWidth);
        break;
      }

      // Stroke (view-relative line width)
      case "KV": {
        const [, r, g, b, a, lineWidth] = cmd;
        doStroke(r, g, b, a, lineWidth / scale);
        break;
      }

      // Set fill color only
      case "FS": {
        const [, r, g, b, a] = cmd;
        state.fillColor = { r, g, b, a };
        break;
      }

      // Set stroke style (coordinate-space)
      case "KS": {
        const [, r, g, b, a, lineWidth] = cmd;
        state.strokeColor = { r, g, b, a };
        state.lineWidth = lineWidth;
        state.lineWidthViewRelative = false;
        break;
      }

      // Set stroke style (view-relative)
      case "KSV": {
        const [, r, g, b, a, lineWidth] = cmd;
        state.strokeColor = { r, g, b, a };
        state.lineWidth = lineWidth;
        state.lineWidthViewRelative = true;
        break;
      }

      // Fill using current style
      case "f": {
        const { r, g, b, a } = state.fillColor;
        doFill(r, g, b, a);
        break;
      }

      // Stroke using current style
      case "k": {
        const { r, g, b, a } = state.strokeColor;
        const w = state.lineWidthViewRelative
          ? state.lineWidth / scale
          : state.lineWidth;
        doStroke(r, g, b, a, w);
        break;
      }

      // Line style
      case "LC": {
        const [, cap] = cmd;
        state.lineCap = lineCapToString(cap);
        break;
      }
      case "LJ": {
        const [, join] = cmd;
        state.lineJoin = lineJoinToString(join);
        break;
      }
      case "LD":
        // Line dash not supported in PixiJS Graphics
        break;
      case "LDV":
        // Line dash not supported in PixiJS Graphics
        break;

      // Text
      case "FT": {
        const [, text, x, y] = cmd;
        const t = new Text({ text, style: { fontFamily: state.font } });
        t.x = x;
        t.y = y;
        t.scale.y = -1; // Counter the Y-axis flip
        const { r, g, b, a } = state.fillColor;
        t.style.fill = rgbaToHex(r, g, b);
        t.alpha = a;
        t.blendMode = state.blendMode as never;
        currentContainer.addChild(t);
        break;
      }
      case "SF": {
        const [, font] = cmd;
        state.font = font;
        break;
      }

      // Composite operation
      case "GCO": {
        const [, operation] = cmd;
        state.blendMode = compositeOpToBlendMode(operation);
        break;
      }

      default:
        console.warn(`Unknown canvas command: ${opcode}`);
    }
  }
}

/** Options for rendering a diagram with PixiJS */
export interface RenderPixiOptions {
  /** Background color (optional) */
  backgroundColor?: Color;
  /** Padding factor for fitting diagram (0-1, default: 0.9 = 10% padding) */
  padding?: number;
}

/**
 * Render a canvas diagram to a PixiJS Application.
 * The Application should already be initialized.
 */
export function renderDiagramPixi(
  app: Application,
  diagram: CanvasDiagram,
  options: RenderPixiOptions = {},
): void {
  const padding = options.padding ?? 0.9;

  // Clear existing stage children
  app.stage.removeChildren();

  // Set background
  if (options.backgroundColor) {
    const { r, g, b, a } = options.backgroundColor;
    app.renderer.background.color = rgbaToHex(r, g, b);
    app.renderer.background.alpha = a;
  }

  // Calculate fit transform
  const transform = calculateFitTransform(
    diagram.width,
    diagram.height,
    diagram.bounds,
    padding,
  );

  // Create root container with the fit transform
  const root = new Container();
  root.setFromMatrix(
    new Matrix(
      transform.a,
      transform.b,
      transform.c,
      transform.d,
      transform.e,
      transform.f,
    ),
  );
  app.stage.addChild(root);

  executeCommandsPixi(root, diagram.commands, transform.scale);
}

/**
 * Create and initialize a PixiJS Application for rendering diagrams.
 * Convenience function that creates an app sized to the diagram.
 */
export async function createPixiApp(
  diagram: CanvasDiagram,
  options: RenderPixiOptions & { pixelRatio?: number } = {},
): Promise<Application> {
  const pixelRatio = options.pixelRatio ?? window.devicePixelRatio ?? 1;
  const app = new Application();
  await app.init({
    width: diagram.width,
    height: diagram.height,
    resolution: pixelRatio,
    autoDensity: true,
    antialias: true,
    background: options.backgroundColor
      ? rgbaToHex(
          options.backgroundColor.r,
          options.backgroundColor.g,
          options.backgroundColor.b,
        )
      : undefined,
    backgroundAlpha: options.backgroundColor?.a ?? 0,
  });
  return app;
}
