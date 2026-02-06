# diagrams-canvas-json-web

TypeScript library for rendering [diagrams-canvas-json](../diagrams-canvas-json) output using HTML Canvas.

## Project Structure

```
diagrams-canvas-json-web/
├── package.json          # Node package with vite & typescript deps
├── tsconfig.json         # TypeScript config for library builds
├── vite.config.ts        # Vite dev server config (port 3000, proxies /api to :8080)
├── src/lib/
│   ├── index.ts          # Library entry point
│   ├── types.ts          # TypeScript types for diagram JSON schema
│   └── renderer.ts       # Canvas rendering implementation
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

1. Start the Haskell server (from project root):
   ```bash
   cabal run diagrams-canvas-json
   ```

2. Start the web dev server:
   ```bash
   cd diagrams-canvas-json-web
   npm run dev
   ```

### What You'll See

The dev server displays all diagram examples from the [diagrams quickstart guide](https://diagrams.github.io/doc/quickstart.html):

- Each example shows as a card with the example name
- Left side: SVG rendered by `diagrams-svg` (fetched from Haskell server)
- Right side: Canvas rendering using `diagrams-canvas-json` (fetched as JSON)

This side-by-side layout allows visual comparison between the two backends.

### API Proxy

The Vite dev server proxies `/api/*` requests to `http://localhost:8080`:

 | Frontend Request              | Proxied To                                     |
 |-------------------------------|------------------------------------------------|
 | `GET /api/examples`           | `http://localhost:8080/api/examples`           |
 | `GET /api/example/:name/svg`  | `http://localhost:8080/api/example/:name/svg`  |
 | `GET /api/example/:name/json` | `http://localhost:8080/api/example/:name/json` |

## Library Usage

```typescript
import { renderDiagram, fetchAndRenderDiagram } from "diagrams-canvas-json-web";
import type { CanvasDiagram, RenderOptions } from "diagrams-canvas-json-web";

// Fetch and render from a URL
const canvas = document.getElementById("my-canvas") as HTMLCanvasElement;
await fetchAndRenderDiagram(canvas, "/api/example/circle/json");

// Or render a diagram object directly
const diagram: CanvasDiagram = {
  width: 400,
  height: 400,
  bounds: { minX: -1, minY: -1, maxX: 1, maxY: 1 },
  commands: [
    ["B"],           // BeginPath
    ["M", 1, 0],     // MoveTo
    ["L", 0, 1],     // LineTo
    ["Z"],           // ClosePath
    ["F", 0, 0, 255, 1]  // Fill blue
  ]
};

renderDiagram(canvas, diagram, {
  backgroundColor: { r: 255, g: 255, b: 255, a: 1 },
  padding: 0.9,  // 10% padding around diagram
});
```

## Scripts

- `npm run dev` - Start Vite dev server
- `npm run build` - Build library and dev assets
- `npm run build:lib` - Build library only (TypeScript compilation)
- `npm run typecheck` - Type check without emitting
- `npm run preview` - Preview production build

## JSON Schema

The library expects diagrams in a compact command-based JSON format:

```typescript
interface CanvasDiagram {
  width: number;    // Requested canvas width
  height: number;   // Requested canvas height
  bounds: BBox;     // Diagram bounding box in diagram coordinates
  commands: CanvasCommand[];  // Drawing commands
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

 | Opcode   | Parameters                      | Description                               |
 |----------|---------------------------------|-------------------------------------------|
 | `S`      | -                               | Save canvas state                         |
 | `R`      | -                               | Restore canvas state                      |
 | `T`      | a, b, c, d, e, f                | Apply transform matrix                    |
 | `B`      | -                               | Begin path                                |
 | `M`      | x, y                            | Move to (absolute)                        |
 | `L`      | x, y                            | Line to (absolute)                        |
 | `C`      | cx1, cy1, cx2, cy2, x, y        | Cubic bezier to                           |
 | `Q`      | cx, cy, x, y                    | Quadratic bezier to                       |
 | `A`      | cx, cy, r, startAngle, endAngle | Arc                                       |
 | `Z`      | -                               | Close path                                |
 | `F`      | r, g, b, a                      | Fill path (RGB 0-255, alpha 0-1)          |
 | `K`      | r, g, b, a, lineWidth           | Stroke path                               |
 | `LC`     | cap                             | Set line cap (0=butt, 1=round, 2=square)  |
 | `LJ`     | join                            | Set line join (0=miter, 1=round, 2=bevel) |
 | `LD`     | ...dashes                       | Set line dash pattern                     |
 | `FT`     | text, x, y                      | Fill text at position                     |
 | `SF`     | font                            | Set font                                  |

### Coordinate System

- The Haskell backend outputs coordinates in diagram space (typically centered at origin)
- The renderer calculates a transform to fit the diagram bounds into the canvas
- The Y-axis is flipped (diagram Y increases upward, canvas Y increases downward)
- Line widths are adjusted by the inverse of the scale to maintain consistent visual width
- Dash patterns are scaled to match the transform

## Current Limitations

- **Line width scaling**: Works for explicit widths but `Measure`-based widths from diagrams don't resolve properly
- **Text**: Basic text works but font sizing needs improvement
- **Gradients**: Only solid colors supported (no gradients or patterns)
