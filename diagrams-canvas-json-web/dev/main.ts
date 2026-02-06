import { renderDiagram, fetchAndRenderDiagram } from "diagrams-canvas-json-web";
import type { Diagram } from "diagrams-canvas-json-web";

const canvas = document.getElementById("diagram-canvas") as HTMLCanvasElement;
const statusEl = document.getElementById("status") as HTMLDivElement;

function setStatus(message: string, type: "info" | "success" | "error" = "info"): void {
  statusEl.textContent = message;
  statusEl.className = `status ${type}`;
}

// Get example name from URL params
const params = new URLSearchParams(window.location.search);
const exampleName = params.get("example") || "basic";

// Highlight active nav link
document.querySelectorAll(".example-list a").forEach((link) => {
  const href = link.getAttribute("href");
  if (href?.includes(`example=${exampleName}`)) {
    link.classList.add("active");
  }
});

// Mock diagrams for development before Haskell server is ready
const mockDiagrams: Record<string, Diagram> = {
  basic: {
    width: 400,
    height: 300,
    primitives: [
      {
        type: "path",
        path: {
          segments: [
            { type: "moveTo", point: { x: 50, y: 50 } },
            { type: "lineTo", point: { x: 350, y: 50 } },
            { type: "lineTo", point: { x: 350, y: 250 } },
            { type: "lineTo", point: { x: 50, y: 250 } },
            { type: "closePath" },
          ],
        },
        stroke: { color: { r: 0, g: 0, b: 0, a: 1 }, width: 2 },
        fill: { color: { r: 200, g: 220, b: 255, a: 1 } },
      },
    ],
  },
  shapes: {
    width: 400,
    height: 300,
    primitives: [
      {
        type: "path",
        path: {
          segments: [
            { type: "arc", center: { x: 100, y: 150 }, radius: 50, startAngle: 0, endAngle: Math.PI * 2 },
          ],
        },
        stroke: { color: { r: 255, g: 0, b: 0, a: 1 }, width: 3 },
        fill: { color: { r: 255, g: 200, b: 200, a: 1 } },
      },
      {
        type: "path",
        path: {
          segments: [
            { type: "moveTo", point: { x: 200, y: 100 } },
            { type: "lineTo", point: { x: 300, y: 100 } },
            { type: "lineTo", point: { x: 300, y: 200 } },
            { type: "lineTo", point: { x: 200, y: 200 } },
            { type: "closePath" },
          ],
        },
        stroke: { color: { r: 0, g: 128, b: 0, a: 1 }, width: 3 },
        fill: { color: { r: 200, g: 255, b: 200, a: 1 } },
      },
    ],
  },
  paths: {
    width: 400,
    height: 300,
    primitives: [
      {
        type: "path",
        path: {
          segments: [
            { type: "moveTo", point: { x: 50, y: 150 } },
            { type: "bezierCurveTo", control1: { x: 100, y: 50 }, control2: { x: 300, y: 250 }, end: { x: 350, y: 150 } },
          ],
        },
        stroke: { color: { r: 128, g: 0, b: 128, a: 1 }, width: 4 },
      },
      {
        type: "path",
        path: {
          segments: [
            { type: "moveTo", point: { x: 50, y: 200 } },
            { type: "quadraticCurveTo", control: { x: 200, y: 50 }, end: { x: 350, y: 200 } },
          ],
        },
        stroke: { color: { r: 0, g: 128, b: 128, a: 1 }, width: 4, dashArray: [10, 5] },
      },
    ],
  },
  transforms: {
    width: 400,
    height: 300,
    primitives: [
      {
        type: "group",
        transform: { a: 1, b: 0, c: 0, d: 1, e: 200, f: 150 },
        children: [
          {
            type: "path",
            path: {
              segments: [
                { type: "moveTo", point: { x: -50, y: -50 } },
                { type: "lineTo", point: { x: 50, y: -50 } },
                { type: "lineTo", point: { x: 50, y: 50 } },
                { type: "lineTo", point: { x: -50, y: 50 } },
                { type: "closePath" },
              ],
            },
            stroke: { color: { r: 0, g: 0, b: 0, a: 1 }, width: 2 },
            fill: { color: { r: 255, g: 200, b: 100, a: 1 } },
          },
          {
            type: "group",
            transform: { a: 0.707, b: 0.707, c: -0.707, d: 0.707, e: 0, f: 0 },
            children: [
              {
                type: "path",
                path: {
                  segments: [
                    { type: "moveTo", point: { x: -30, y: -30 } },
                    { type: "lineTo", point: { x: 30, y: -30 } },
                    { type: "lineTo", point: { x: 30, y: 30 } },
                    { type: "lineTo", point: { x: -30, y: 30 } },
                    { type: "closePath" },
                  ],
                },
                stroke: { color: { r: 0, g: 0, b: 128, a: 1 }, width: 2 },
                fill: { color: { r: 100, g: 150, b: 255, a: 0.7 } },
              },
            ],
          },
        ],
      },
    ],
  },
};

async function loadDiagram(): Promise<void> {
  try {
    // Try to fetch from Haskell server first
    const apiUrl = `/api/examples/${exampleName}`;
    setStatus(`Fetching from ${apiUrl}...`);

    try {
      const diagram = await fetchAndRenderDiagram(canvas, apiUrl, {
        backgroundColor: { r: 255, g: 255, b: 255, a: 1 },
      });
      setStatus(`Rendered diagram: ${diagram.width}x${diagram.height} with ${diagram.primitives.length} primitive(s)`, "success");
    } catch {
      // Fall back to mock data if Haskell server is not running
      setStatus(`Haskell server not available, using mock data for "${exampleName}"`, "info");
      const mockDiagram = mockDiagrams[exampleName];
      if (mockDiagram) {
        renderDiagram(canvas, mockDiagram, {
          backgroundColor: { r: 255, g: 255, b: 255, a: 1 },
        });
        setStatus(`Rendered mock diagram: ${mockDiagram.width}x${mockDiagram.height} with ${mockDiagram.primitives.length} primitive(s)`, "success");
      } else {
        setStatus(`Unknown example: "${exampleName}"`, "error");
      }
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    setStatus(`Error: ${message}`, "error");
  }
}

loadDiagram();
