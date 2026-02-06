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
    ├── index.html        # Dev server page with example navigation
    └── main.ts           # Dev entry point with mock diagrams
```

## Development

```bash
npm install
npm run dev
```

The dev server runs on `http://localhost:3000` with:
- Navigation for different examples (basic, shapes, paths, transforms)
- Mock diagrams for development before the Haskell server is ready
- API proxy forwarding `/api/*` requests to `http://localhost:8080`

When the Haskell server is running and serving JSON at `/api/examples/{name}`, it will fetch from there; otherwise it falls back to mock data.

## Library Usage

```typescript
import { renderDiagram, fetchAndRenderDiagram } from "diagrams-canvas-json-web";
import type { Diagram } from "diagrams-canvas-json-web";

// Render a diagram object directly
const diagram: Diagram = { width: 400, height: 300, primitives: [...] };
renderDiagram(canvas, diagram, {
  backgroundColor: { r: 255, g: 255, b: 255, a: 1 },
});

// Fetch and render from a URL
await fetchAndRenderDiagram(canvas, "/api/examples/basic");
```

## Scripts

- `npm run dev` - Start Vite dev server
- `npm run build` - Build library and dev assets
- `npm run build:lib` - Build library only (TypeScript compilation)
- `npm run typecheck` - Type check without emitting
- `npm run preview` - Preview production build

## JSON Schema

The library expects diagrams in a JSON format with the following structure (see `src/lib/types.ts` for full type definitions):

```typescript
interface Diagram {
  width: number;
  height: number;
  primitives: Primitive[];
}
```

Primitives can be:
- `path` - A path with segments (moveTo, lineTo, curves, arcs), optional stroke and fill
- `text` - Text at a position with optional font and fill
- `group` - A group of child primitives with an optional transform

These types will evolve as the Haskell package develops its JSON schema.
