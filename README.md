# diagrams-canvas-json

A diagrams backend that encodes drawings as JSON to be rendered in a browser using the Canvas API.

## Project Structure

```
diagrams-canvas-json/
├── diagrams-canvas-json/       # Haskell library and development server
│   ├── src/                    # Library source (diagrams backend)
│   ├── exe/                    # Development server executable
│   └── diagrams-canvas-json.cabal
├── diagrams-canvas-json-web/   # TypeScript/Canvas rendering library
│   ├── src/lib/                # Library source (canvas renderer + viewer)
│   └── dev/                    # Development frontend
├── gerber-diagrams-canvas-json/ # Gerber PCB artwork to canvas JSON
│   ├── src/                    # Library source (gerber rendering + compositing)
│   ├── exe/                    # CLI tool (to-json, view, board-to-json, etc.)
│   ├── data/                   # Test gerber and SVG reference data
│   └── gerber-diagrams-canvas-json.cabal
├── cabal.project               # Cabal project config
└── flake.nix                   # Nix flake for development environment
```

## Packages

### diagrams-canvas-json (Haskell)

A diagrams backend that renders to compact JSON command arrays for Canvas execution. Features:

- **Coordinate-space vs view-relative line widths**: `K`/`KS` commands scale with the diagram transform (for gerber traces, local/global measures); `KV`/`KSV` commands maintain constant visual width regardless of zoom (for normalized/output measures like `veryThick`, `thin`, etc.)
- **Independent dash pattern modes**: `LD` (coordinate-space) and `LDV` (view-relative), classified separately from line width
- **Fill/stroke separation**: Only closed paths are filled; stroke is skipped when lineWidth=0; alpha is multiplied by fill/stroke opacity attributes
- **Command optimization**: Consecutive Save/Restore groups sharing the same context are collapsed into set-only commands (`FS`, `KS`, `KSV`); transparent fills and strokes are stripped
- **Configurable JSON precision**: Per-category decimal place control (coordinates, alpha, transforms, line widths, dashes, angles) using `Scientific` numbers to avoid IEEE 754 bloat
- **Measure classification**: Line width and dashing measures are classified by probing `unmeasureAttrs` with different normalized-to-output scales, correctly handling `local`, `global`, `normalized`, `output`, and `atLeast` combinations

### gerber-diagrams-canvas-json (Haskell)

Converts Gerber PCB artwork files to canvas JSON with post-processing for multi-layer board visualization. Features:

- **Polarity compositing**: Dark/clear shapes via `destination-out` canvas blending
- **Outline extraction**: Contour welding with spatial index for joining segments by endpoint proximity, detecting board outline vs cutouts
- **Layer clipping**: Constrain layer content to board outline via `destination-in` compositing
- **Multi-layer board rendering**: Configurable layer stack with colors, outline modes, base color, and prepreg color (`BoardSpec`)
- **Automatic JSON precision**: Coordinate precision derived from Gerber format spec and unit conversion

CLI tool with commands: `to-json`, `view`, `outline-to-json`, `outline-view`, `composite-to-json`, `composite-view`, `clip-to-json`, `clip-view`, `board-to-json`, `board-view`.

### diagrams-canvas-json-web (TypeScript)

TypeScript library for rendering canvas JSON output in the browser. Features:

- **Canvas renderer**: Interprets the command stream onto an HTML Canvas context
- **Pan/zoom viewer**: `createViewer()` with mouse wheel zoom, drag pan, stacked canvas layers for compositing, and checkerboard transparency background
- **Command and custom layers**: Render pre-colored command layers and custom overlay layers sharing the same pan/zoom transform
- **View-relative support**: `KV`/`KSV` and `LDV` commands are divided by the current zoom scale for constant visual appearance

## Quick Start

### Prerequisites

- GHC 9.10+ with cabal
- Node.js 18+

### Running the Development Environment

1. **Start both the back-end and front-end dev servers** with the just command.

   ```
   just dev
   ```

   Or Start them manually
   - **Start the Haskell server** (serves SVG examples on port 8080):

     ```bash
     cabal run diagrams-canvas-json
     ```

   - **Start the web dev server** (serves frontend on port 3000):
     ```bash
     cd diagrams-canvas-json-web
     npm install
     npm run dev
     ```

2. **Open** http://localhost:3000 to see the examples

## API Endpoints

The Haskell server provides:

| Endpoint                      | Description                      |
| ----------------------------- | -------------------------------- |
| `GET /api/examples`           | List all available example names |
| `GET /api/example/:name/svg`  | Get SVG for a specific example   |
| `GET /api/example/:name/json` | Get JSON for canvas rendering    |
| `GET /api/health`             | Health check                     |

### Available Examples

Examples from the diagrams quickstart guide:

- `circle` - Simple unfilled circle
- `styled-circle` - Blue circle with dashed purple outline
- `side-by-side` - Red and green circles horizontally
- `superimposed` - Aqua square on top of circle
- `origin` - Circle showing its local origin
- `horizontal` - Circle and square side-by-side
- `vertical` - Circle and square stacked
- `grid` - Grid of circles with varying sizes
- `beside-vectors` - Shapes positioned using vectors
- `rotated-ellipses` - Scaled and rotated circles
- `snug-ellipses` - Tangent ellipses using snug positioning
- `transformations` - Various scale and rotation transforms
- `translation` - Translated circle showing origin
- `translation-effects` - Translation in different contexts
- `alignment` - Circles aligned along top edges
- `hexagon` - Regular hexagon
- `polygon-nodes` - Green circles at hexagon vertices
- `tournament` - Numbered nodes in pentagon arrangement

## Dev Setup Architecture

```
+---------------------+     +---------------------+
|   Haskell Server    |     |   Vite Dev Server   |
|   (port 8080)       |     |   (port 3000)       |
|                     |     |                     |
|  +---------------+  |     |  +---------------+  |
|  | diagrams-svg  |  |     |  |   Frontend    |  |
|  | (SVG output)  |--+-----+->|  (displays    |  |
|  +---------------+  |     |  |   both)       |  |
|                     |     |  +---------------+  |
|  +---------------+  |     |                     |
|  | diagrams-     |  |     |  +---------------+  |
|  | canvas-json   |  |     |  | canvas        |  |
|  | (JSON output) |--+-----+->| renderer      |  |
|  +---------------+  |     |  +---------------+  |
+---------------------+     +---------------------+
```

The Vite dev server proxies `/api/*` requests to the Haskell server at `localhost:8080`.

## JSON Schema

The backend outputs a compact command-based JSON format:

```json
{
  "width": 400,
  "height": 400,
  "bounds": { "minX": -1, "minY": -1, "maxX": 1, "maxY": 1 },
  "commands": [
    ["S"],
    ["B"],
    ["M", 1, 0],
    ["C", 1, 0.5523, 0.5523, 1, 0, 1],
    ["Z"],
    ["F", 0, 0, 255, 1],
    ["KV", 128, 0, 128, 1, 4],
    ["R"]
  ]
}
```

See `diagrams-canvas-json-web/src/lib/types.ts` for full command definitions.

## Current Limitations

- **Text rendering**: Basic text rendering works but font sizing and alignment
  need improvement.
- **Gradients and patterns**: Only solid color fills and strokes are supported.
- **Pure `output` measures**: Measures using only `output` (without `normalized`
  via `atLeast`) may not be classified correctly as view-relative. In practice
  this is rare since the standard diagrams line width constants all use
  `normalized ... `atLeast` output ...`.

## Example output of dev server

![Dev server example output](images/dev-server-example-output.png)

## License

MIT
