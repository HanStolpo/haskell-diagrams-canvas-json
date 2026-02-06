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
│   ├── src/lib/                # Library source (canvas renderer)
│   └── dev/                    # Development frontend
├── cabal.project               # Cabal project config
└── flake.nix                   # Nix flake for development environment
```

## Current Status

The canvas backend is functional and renders most diagrams correctly:

- **Haskell Backend**: Encodes diagrams as compact JSON command arrays
- **TypeScript Renderer**: Executes commands on HTML Canvas with proper scaling
- **Development UI**: Side-by-side comparison of `diagrams-svg` vs `diagrams-canvas-json`

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
 |-------------------------------|----------------------------------|
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
    ["S"],                              // Save
    ["B"],                              // BeginPath
    ["M", 1, 0],                        // MoveTo x y
    ["C", 1, 0.55, 0.55, 1, 0, 1],     // BezierTo cx1 cy1 cx2 cy2 x y
    ["Z"],                              // ClosePath
    ["F", 0, 0, 255, 1],               // Fill r g b a (0-255 for RGB, 0-1 for alpha)
    ["K", 0, 0, 0, 1, 2],              // Stroke r g b a lineWidth
    ["R"]                               // Restore
  ]
}
```

See `diagrams-canvas-json-web/src/lib/types.ts` for full command definitions.

## Current Limitations

- **Measure-based line widths**: Line width attributes like `veryThick`,
  `thick`, etc. that use the `Measure` type don't resolve properly. Only
  explicit `Output` measure widths work correctly.
- **Text rendering**: Basic text rendering works but font sizing and alignment
  need improvement.
- **Gradients and patterns**: Only solid color fills and strokes are supported.

## Future Improvements

- [ ] Proper `Measure` resolution for line widths (requires passing global-to-output transformation)
- [ ] Font size resolution from `Measure` values
- [ ] Text alignment support (currently ignores alignment)
- [ ] Gradient and pattern fill support
- [ ] Clip path support
- [ ] Image embedding
- [ ] Performance optimization for large diagrams

## Example output of dev server

![Dev server example output](images/dev-server-example-output.png)

## Roadmap

1. [x] Set up project structure
2. [x] Create development server with SVG examples
3. [x] Create web frontend to display examples
4. [x] Implement `diagrams-canvas-json` backend (JSON output)
5. [x] Implement canvas renderer for JSON diagrams
6. [x] Add side-by-side SVG vs Canvas comparison in dev UI
7. [ ] Resolve `Measure`-based attributes properly
8. [ ] Add comprehensive test suite
9. [ ] Publish to Hackage and npm

## License

MIT
