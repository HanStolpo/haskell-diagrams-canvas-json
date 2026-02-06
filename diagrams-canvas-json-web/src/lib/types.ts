/**
 * Types representing the JSON structure produced by diagrams-canvas-json
 * These will be updated as the Haskell package develops its JSON schema
 */

/** A 2D point */
export interface Point {
  x: number;
  y: number;
}

/** RGBA color representation */
export interface Color {
  r: number;
  g: number;
  b: number;
  a: number;
}

/** Line cap style */
export type LineCap = "butt" | "round" | "square";

/** Line join style */
export type LineJoin = "miter" | "round" | "bevel";

/** Stroke style for paths */
export interface StrokeStyle {
  color: Color;
  width: number;
  lineCap?: LineCap;
  lineJoin?: LineJoin;
  dashArray?: number[];
  dashOffset?: number;
}

/** Fill style for shapes */
export interface FillStyle {
  color: Color;
}

/** Transform matrix (2D affine transformation) */
export interface Transform {
  a: number;
  b: number;
  c: number;
  d: number;
  e: number;
  f: number;
}

/** Path segment commands */
export type PathSegment =
  | { type: "moveTo"; point: Point }
  | { type: "lineTo"; point: Point }
  | { type: "quadraticCurveTo"; control: Point; end: Point }
  | { type: "bezierCurveTo"; control1: Point; control2: Point; end: Point }
  | { type: "arcTo"; control1: Point; control2: Point; radius: number }
  | { type: "arc"; center: Point; radius: number; startAngle: number; endAngle: number; counterclockwise?: boolean }
  | { type: "closePath" };

/** A path definition */
export interface Path {
  segments: PathSegment[];
}

/** Drawing primitive types */
export type Primitive =
  | { type: "path"; path: Path; stroke?: StrokeStyle; fill?: FillStyle }
  | { type: "text"; text: string; position: Point; font?: string; fill?: FillStyle }
  | { type: "group"; children: Primitive[]; transform?: Transform };

/** Root diagram structure */
export interface Diagram {
  width: number;
  height: number;
  primitives: Primitive[];
}
