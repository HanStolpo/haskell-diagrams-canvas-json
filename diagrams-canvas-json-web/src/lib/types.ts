/**
 * Types representing the JSON structure produced by diagrams-canvas-json
 *
 * The backend produces a command-based format where each command is a compact
 * JSON array with a string opcode followed by parameters.
 */

/** RGBA color representation */
export interface Color {
  r: number;
  g: number;
  b: number;
  a: number;
}

/** Bounding box of the diagram in diagram coordinates */
export interface BBox {
  minX: number;
  minY: number;
  maxX: number;
  maxY: number;
}

/**
 * Canvas command opcodes produced by the Haskell backend.
 * Commands are encoded as JSON arrays for compact wire format.
 */
export type CanvasCommand =
  // State management
  | ["S"] // Save
  | ["R"] // Restore
  // Transformation (a, b, c, d, e, f) - standard 2D affine matrix
  | ["T", number, number, number, number, number, number]
  // Path commands (all use ABSOLUTE coordinates in diagram space)
  | ["B"] // BeginPath
  | ["M", number, number] // MoveTo x, y
  | ["L", number, number] // LineTo x, y
  | ["C", number, number, number, number, number, number] // BezierTo cx1, cy1, cx2, cy2, x, y
  | ["Q", number, number, number, number] // QuadTo cx, cy, x, y
  | ["A", number, number, number, number, number] // Arc cx, cy, r, startAngle, endAngle
  | ["Z"] // ClosePath
  // Style and drawing
  | ["F", number, number, number, number] // Fill RGBA (0-255 for RGB, 0-1 for alpha)
  | ["K", number, number, number, number, number] // Stroke RGBA + lineWidth
  | ["LC", number] // SetLineCap: 0=butt, 1=round, 2=square
  | ["LJ", number] // SetLineJoin: 0=miter, 1=round, 2=bevel
  | ["LD", ...number[]] // SetLineDash: array of dash lengths
  // Text
  | ["FT", string, number, number] // FillText text, x, y
  | ["SF", string]; // SetFont font

/** Root diagram structure from the backend */
export interface CanvasDiagram {
  width: number;
  height: number;
  bounds: BBox;
  commands: CanvasCommand[];
}
