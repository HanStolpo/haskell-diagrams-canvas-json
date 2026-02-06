import type {
  Diagram,
  Primitive,
  Path,
  PathSegment,
  StrokeStyle,
  FillStyle,
  Transform,
  Color,
} from "./types.js";

/** Convert Color to CSS rgba string */
function colorToCss(color: Color): string {
  return `rgba(${color.r}, ${color.g}, ${color.b}, ${color.a})`;
}

/** Apply stroke style to canvas context */
function applyStrokeStyle(ctx: CanvasRenderingContext2D, style: StrokeStyle): void {
  ctx.strokeStyle = colorToCss(style.color);
  ctx.lineWidth = style.width;
  if (style.lineCap) ctx.lineCap = style.lineCap;
  if (style.lineJoin) ctx.lineJoin = style.lineJoin;
  if (style.dashArray) ctx.setLineDash(style.dashArray);
  if (style.dashOffset) ctx.lineDashOffset = style.dashOffset;
}

/** Apply fill style to canvas context */
function applyFillStyle(ctx: CanvasRenderingContext2D, style: FillStyle): void {
  ctx.fillStyle = colorToCss(style.color);
}

/** Apply transform to canvas context */
function applyTransform(ctx: CanvasRenderingContext2D, transform: Transform): void {
  ctx.transform(transform.a, transform.b, transform.c, transform.d, transform.e, transform.f);
}

/** Render a path to the canvas context */
function renderPath(ctx: CanvasRenderingContext2D, path: Path): void {
  ctx.beginPath();
  for (const segment of path.segments) {
    renderPathSegment(ctx, segment);
  }
}

/** Render a single path segment */
function renderPathSegment(ctx: CanvasRenderingContext2D, segment: PathSegment): void {
  switch (segment.type) {
    case "moveTo":
      ctx.moveTo(segment.point.x, segment.point.y);
      break;
    case "lineTo":
      ctx.lineTo(segment.point.x, segment.point.y);
      break;
    case "quadraticCurveTo":
      ctx.quadraticCurveTo(segment.control.x, segment.control.y, segment.end.x, segment.end.y);
      break;
    case "bezierCurveTo":
      ctx.bezierCurveTo(
        segment.control1.x,
        segment.control1.y,
        segment.control2.x,
        segment.control2.y,
        segment.end.x,
        segment.end.y
      );
      break;
    case "arcTo":
      ctx.arcTo(
        segment.control1.x,
        segment.control1.y,
        segment.control2.x,
        segment.control2.y,
        segment.radius
      );
      break;
    case "arc":
      ctx.arc(
        segment.center.x,
        segment.center.y,
        segment.radius,
        segment.startAngle,
        segment.endAngle,
        segment.counterclockwise ?? false
      );
      break;
    case "closePath":
      ctx.closePath();
      break;
  }
}

/** Render a primitive to the canvas */
function renderPrimitive(ctx: CanvasRenderingContext2D, primitive: Primitive): void {
  switch (primitive.type) {
    case "path":
      renderPath(ctx, primitive.path);
      if (primitive.fill) {
        applyFillStyle(ctx, primitive.fill);
        ctx.fill();
      }
      if (primitive.stroke) {
        applyStrokeStyle(ctx, primitive.stroke);
        ctx.stroke();
      }
      break;

    case "text":
      if (primitive.font) ctx.font = primitive.font;
      if (primitive.fill) {
        applyFillStyle(ctx, primitive.fill);
        ctx.fillText(primitive.text, primitive.position.x, primitive.position.y);
      }
      break;

    case "group":
      ctx.save();
      if (primitive.transform) {
        applyTransform(ctx, primitive.transform);
      }
      for (const child of primitive.children) {
        renderPrimitive(ctx, child);
      }
      ctx.restore();
      break;
  }
}

/** Options for rendering a diagram */
export interface RenderOptions {
  /** Whether to clear the canvas before rendering (default: true) */
  clear?: boolean;
  /** Background color to fill before rendering (optional) */
  backgroundColor?: Color;
  /** Scale factor for high-DPI displays (default: window.devicePixelRatio) */
  pixelRatio?: number;
}

/**
 * Render a diagram to an HTML canvas element
 */
export function renderDiagram(
  canvas: HTMLCanvasElement,
  diagram: Diagram,
  options: RenderOptions = {}
): void {
  const ctx = canvas.getContext("2d");
  if (!ctx) {
    throw new Error("Could not get 2D rendering context from canvas");
  }

  const pixelRatio = options.pixelRatio ?? window.devicePixelRatio ?? 1;

  // Set canvas size accounting for pixel ratio
  canvas.width = diagram.width * pixelRatio;
  canvas.height = diagram.height * pixelRatio;
  canvas.style.width = `${diagram.width}px`;
  canvas.style.height = `${diagram.height}px`;

  // Scale context for pixel ratio
  ctx.scale(pixelRatio, pixelRatio);

  // Clear canvas if requested
  if (options.clear !== false) {
    ctx.clearRect(0, 0, diagram.width, diagram.height);
  }

  // Fill background if specified
  if (options.backgroundColor) {
    ctx.fillStyle = colorToCss(options.backgroundColor);
    ctx.fillRect(0, 0, diagram.width, diagram.height);
  }

  // Render all primitives
  for (const primitive of diagram.primitives) {
    renderPrimitive(ctx, primitive);
  }
}

/**
 * Fetch a diagram from a URL and render it
 */
export async function fetchAndRenderDiagram(
  canvas: HTMLCanvasElement,
  url: string,
  options: RenderOptions = {}
): Promise<Diagram> {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Failed to fetch diagram: ${response.status} ${response.statusText}`);
  }
  const diagram: Diagram = await response.json();
  renderDiagram(canvas, diagram, options);
  return diagram;
}
