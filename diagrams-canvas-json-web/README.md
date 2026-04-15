# diagrams-canvas-json-web

TypeScript library for rendering [diagrams-canvas-json](../diagrams-canvas-json) output using HTML Canvas.

## Project Structure

```
diagrams-canvas-json-web/
├── package.json          # Node package with vite, typescript, pixi.js deps
├── tsconfig.json         # TypeScript config for library builds
├── vite.config.ts        # Vite dev server config (port 3000, proxies /api to :8080)
├── vite.lib.config.ts    # Vite config for Canvas 2D IIFE bundle
├── vite.pixi.config.ts   # Vite config for PixiJS IIFE bundle (includes pixi.js)
├── src/lib/
│   ├── index.ts          # Library entry point (Canvas 2D)
│   ├── pixi.ts           # Library entry point (PixiJS backend)
│   ├── types.ts          # TypeScript types for diagram JSON schema
│   ├── renderer.ts       # Canvas 2D rendering implementation
│   ├── renderer-pixi.ts  # PixiJS rendering implementation
│   ├── viewer.ts         # Pan/zoom layered viewer (Canvas 2D)
│   └── viewer-pixi.ts    # Pan/zoom layered viewer (PixiJS, mask-texture compositing)
└── dev/
    ├── index.html        # Dev server page
    └── main.ts           # Dev entry point - fetches and displays examples
```

## Development

```bash
npm install
npm run dev
```

The dev server runs on `http://localhost:3000` and requires the Haskell server to be running on port 8080.

### Starting Both Servers

From the project root, use the justfile to run both servers together:

```bash
just dev
```

Or start them individually:

1. Start the Haskell dev server (from project root):

   ```bash
   cabal run diagrams-canvas-json-dev
   ```

2. Start the web dev server:
   ```bash
   cd diagrams-canvas-json-web
   npm run dev
   ```

### What You'll See

The dev server displays all diagram examples from the [diagrams quickstart guide](https://diagrams.github.io/doc/quickstart.html):

- Each example shows as a card with the example name
- Left: SVG rendered by `diagrams-svg` (fetched from Haskell server)
- Middle: Canvas 2D rendering using `diagrams-canvas-json` (fetched as JSON)
- Right: PixiJS (WebGL) rendering of the same JSON

This side-by-side layout allows visual comparison between the two backends.

### API Proxy

The Vite dev server proxies `/api/*` requests to `http://localhost:8080`:

| Frontend Request              | Proxied To                                     |
| ----------------------------- | ---------------------------------------------- |
| `GET /api/examples`           | `http://localhost:8080/api/examples`           |
| `GET /api/example/:name/svg`  | `http://localhost:8080/api/example/:name/svg`  |
| `GET /api/example/:name/json` | `http://localhost:8080/api/example/:name/json` |

## Library Usage

### Basic Rendering

```typescript
import { renderDiagram } from "diagrams-canvas-json-web";
import type { CanvasDiagram } from "diagrams-canvas-json-web";

const canvas = document.getElementById("my-canvas") as HTMLCanvasElement;

const diagram: CanvasDiagram = {
  width: 400,
  height: 400,
  bounds: { minX: -1, minY: -1, maxX: 1, maxY: 1 },
  commands: [
    ["B"],
    ["M", 1, 0],
    ["C", 1, 0.5523, 0.5523, 1, 0, 1],
    ["Z"],
    ["F", 0, 0, 255, 1],
  ],
};

renderDiagram(canvas, diagram, {
  backgroundColor: { r: 255, g: 255, b: 255, a: 1 },
  padding: 0.9,
});
```

### Pan/Zoom Viewer

```typescript
import { createViewer } from "diagrams-canvas-json-web";
import type { CommandLayer, BBox } from "diagrams-canvas-json-web";

const container = document.getElementById("viewer")!;
const bounds: BBox = { minX: 0, minY: 0, maxX: 100, maxY: 100 };
const layers: CommandLayer[] = [
  { color: [184, 115, 51, 1], commands: copperCommands },
  { color: [0, 100, 0, 0.85], commands: solderMaskCommands },
];

const viewer = createViewer({
  container,
  bounds,
  commandLayers: layers,
  // background: '#ffffff',  // solid background (default: checkerboard)
  // padding: 0.9,           // 10% padding around diagram
});

// Update layers dynamically
viewer.setCommandLayers(newLayers);

// Add custom overlay layers
viewer.setCustomLayers([
  {
    render: (ctx, scale) => {
      // Draw with the current pan/zoom transform already applied
      ctx.strokeStyle = "red";
      ctx.lineWidth = 2 / scale; // constant visual width
      ctx.strokeRect(10, 10, 50, 50);
    },
  },
]);

// Clean up when done
viewer.destroy();
```

### PixiJS Rendering

An alternative renderer using [PixiJS 8.x](https://pixijs.com/) for WebGL/WebGPU-accelerated rendering. It interprets the same `CanvasCommand[]` stream as the Canvas 2D renderer. Import from the separate `./pixi` entry point to keep PixiJS tree-shakeable for users who only need Canvas 2D.

```typescript
import { Application } from "pixi.js";
import { renderDiagramPixi } from "diagrams-canvas-json-web/pixi";
import type { CanvasDiagram } from "diagrams-canvas-json-web/pixi";

const app = new Application();
await app.init({
  width: diagram.width,
  height: diagram.height,
  antialias: true,
});
document.body.appendChild(app.canvas);

renderDiagramPixi(app, diagram, {
  backgroundColor: { r: 255, g: 255, b: 255, a: 1 },
  padding: 0.9,
});
```

Or use the convenience `createPixiApp` helper:

```typescript
import {
  createPixiApp,
  renderDiagramPixi,
} from "diagrams-canvas-json-web/pixi";

const app = await createPixiApp(diagram, {
  backgroundColor: { r: 255, g: 255, b: 255, a: 1 },
});
renderDiagramPixi(app, diagram, {
  backgroundColor: { r: 255, g: 255, b: 255, a: 1 },
});
document.body.appendChild(app.canvas);
```

### PixiJS Pan/Zoom Viewer

A PixiJS-based pan/zoom viewer with mask-texture compositing for correct gerber layer rendering:

```typescript
import { createPixiViewer } from "diagrams-canvas-json-web/pixi";
import type { CommandLayer, BBox } from "diagrams-canvas-json-web/pixi";

const container = document.getElementById("viewer")!;
const bounds: BBox = { minX: 0, minY: 0, maxX: 100, maxY: 100 };
const layers: CommandLayer[] = [
  { color: [184, 115, 51, 1], commands: copperCommands },
  { color: [0, 100, 0, 0.85], commands: solderMaskCommands },
];

const viewer = await createPixiViewer({
  container,
  bounds,
  commandLayers: layers,
  // background: '#ffffff',  // solid background (default: checkerboard)
  // padding: 0.9,           // 10% padding around diagram
});

// Update layers dynamically
viewer.setCommandLayers(newLayers);

// Clean up when done
viewer.destroy();
```

Each layer is rendered as white-on-transparent to a RenderTexture at viewport resolution, then displayed as a tinted Sprite. This correctly handles gerber polarity compositing: `destination-out` (punch holes) uses the PixiJS `erase` blend mode within the RenderTexture, and `destination-in` (clip to outline) uses a second RenderTexture as a PixiJS mask.

#### PixiJS Limitations

- **Line dash patterns** (`LD`, `LDV`): Not supported — PixiJS Graphics has no native dash API. Dashed lines render as solid.
- **Composite operations** (`GCO`): Common modes (`source-over`, `multiply`, `screen`, `destination-out`, etc.) are mapped to PixiJS blend modes. Unsupported operations fall back to `normal` with a console warning.
- **Curve tessellation**: PixiJS always tessellates curves into line segments internally. The renderer uses `smoothness: 0.99` to ensure high-quality tessellation even for small diagram-space coordinates, but this means more vertices than Canvas 2D which renders true curves.
- **WebGL context limits**: Browsers limit active WebGL contexts (~16). Creating many PixiJS Applications simultaneously will cause earlier contexts to be lost. The dev app works around this by sharing a single Application and extracting rendered images.
- **Text rendering**: Uses PixiJS `Text` objects with a Y-axis counter-flip. Font parsing from the CSS font string is basic.

## Scripts

- `npm run dev` - Start Vite dev server
- `npm run build` - Build library and dev assets
- `npm run build:lib` - Build library only (TypeScript compilation)
- `npm run build:bundle` - Build Canvas 2D IIFE bundle for CLI viewers
- `npm run build:bundle-pixi` - Build PixiJS IIFE bundle for CLI viewers
- `npm run typecheck` - Type check without emitting
- `npm run preview` - Preview production build

## JSON Schema

The library expects diagrams in a compact command-based JSON format:

```typescript
interface CanvasDiagram {
  width: number; // Requested canvas width
  height: number; // Requested canvas height
  bounds: BBox; // Diagram bounding box in diagram coordinates
  commands: CanvasCommand[]; // Drawing commands
}

interface BBox {
  minX: number;
  minY: number;
  maxX: number;
  maxY: number;
}
```

### Command Format

Commands are encoded as compact JSON arrays with a string opcode followed by parameters:

| Opcode | Parameters                      | Description                                                      |
| ------ | ------------------------------- | ---------------------------------------------------------------- |
| `S`    | -                               | Save canvas state                                                |
| `R`    | -                               | Restore canvas state                                             |
| `T`    | a, b, c, d, e, f                | Apply transform matrix                                           |
| `B`    | -                               | Begin path                                                       |
| `M`    | x, y                            | Move to (absolute)                                               |
| `L`    | x, y                            | Line to (absolute)                                               |
| `C`    | cx1, cy1, cx2, cy2, x, y        | Cubic bezier to                                                  |
| `Q`    | cx, cy, x, y                    | Quadratic bezier to                                              |
| `A`    | cx, cy, r, startAngle, endAngle | Arc                                                              |
| `Z`    | -                               | Close path                                                       |
| `F`    | r, g, b, a                      | Fill path (RGB 0-255, alpha 0-1)                                 |
| `K`    | r, g, b, a, lineWidth           | Stroke path (line width in diagram coords, scales with diagram)  |
| `KV`   | r, g, b, a, lineWidth           | Stroke path (line width relative to view, constant visual width) |
| `FS`   | r, g, b, a                      | Set fill color only (no fill operation)                          |
| `KS`   | r, g, b, a, lineWidth           | Set stroke color + line width in diagram coords only             |
| `KSV`  | r, g, b, a, lineWidth           | Set stroke color + line width relative to view only              |
| `f`    | -                               | Fill using current fill style                                    |
| `k`    | -                               | Stroke using current stroke style                                |
| `LC`   | cap                             | Set line cap (0=butt, 1=round, 2=square)                         |
| `LJ`   | join                            | Set line join (0=miter, 1=round, 2=bevel)                        |
| `LD`   | ...dashes                       | Set line dash pattern (diagram coords)                           |
| `LDV`  | ...dashes                       | Set line dash pattern (relative to view)                         |
| `FT`   | text, x, y                      | Fill text at position                                            |
| `SF`   | font                            | Set font                                                         |
| `GCO`  | operation                       | Set globalCompositeOperation (e.g. "destination-out")            |

### Coordinate-Space vs View-Relative

Line widths and dash patterns come in two modes:

- **Coordinate-space** (`K`, `KS`, `LD`): Values are in diagram units and scale with the diagram transform. Used for things like PCB trace widths where the width is part of the geometry.
- **View-relative** (`KV`, `KSV`, `LDV`): Values are in pixels and maintain constant visual size regardless of zoom level. Used for UI-style line widths like `thin`, `thick`, `veryThick`, etc. The renderer divides these values by the current zoom scale.

### Coordinate System

- The Haskell backend outputs coordinates in diagram space (typically centered at origin)
- The renderer calculates a transform to fit the diagram bounds into the canvas
- The Y-axis is flipped (diagram Y increases upward, canvas Y increases downward)

## Current Limitations

- **Text**: Basic text works but font sizing needs improvement
- **Gradients**: Only solid colors supported (no gradients or patterns)
