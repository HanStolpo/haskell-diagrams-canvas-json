import type { CanvasDiagram } from "../src/lib/index.js";
import { renderDiagram } from "../src/lib/index.js";

const statusEl = document.getElementById("status") as HTMLDivElement;
const examplesContainer = document.getElementById("examples") as HTMLDivElement;

function setStatus(
  message: string,
  type: "info" | "success" | "error" = "info",
): void {
  statusEl.textContent = message;
  statusEl.className = `status ${type}`;
}

function createExampleCard(name: string): HTMLElement {
  const card = document.createElement("div");
  card.className = "example-card";
  card.innerHTML = `
    <div class="example-header">${name}</div>
    <div class="example-content">
      <div class="example-pane svg-pane loading" id="svg-${name}">
        Loading SVG...
      </div>
      <div class="example-pane canvas-pane loading" id="canvas-${name}">
        Loading Canvas...
      </div>
    </div>
  `;
  return card;
}

async function loadSvgForExample(name: string): Promise<void> {
  const svgPane = document.getElementById(`svg-${name}`);
  if (!svgPane) return;

  try {
    const response = await fetch(`/api/example/${name}/svg`);
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`);
    }
    const svgText = await response.text();

    // Create an img element with data URI for the SVG
    const img = document.createElement("img");
    img.src = `data:image/svg+xml;base64,${btoa(svgText)}`;
    img.alt = `${name} diagram (SVG)`;

    svgPane.innerHTML = "";
    svgPane.className = "example-pane svg-pane";
    svgPane.appendChild(img);
  } catch (err) {
    svgPane.className = "example-pane svg-pane error";
    svgPane.textContent = `Failed to load: ${err instanceof Error ? err.message : String(err)}`;
  }
}

async function loadCanvasForExample(name: string): Promise<void> {
  const canvasPane = document.getElementById(`canvas-${name}`);
  if (!canvasPane) return;

  try {
    // Create a canvas element
    const canvas = document.createElement("canvas");

    // Fetch and render the diagram
    const response = await fetch(`/api/example/${name}/json`);
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`);
    }
    const diagram: CanvasDiagram = await response.json();
    renderDiagram(canvas, diagram, {
      backgroundColor: { r: 255, g: 255, b: 255, a: 1 },
    });

    canvasPane.innerHTML = "";
    canvasPane.className = "example-pane canvas-pane";
    canvasPane.appendChild(canvas);
  } catch (err) {
    canvasPane.className = "example-pane canvas-pane error";
    canvasPane.textContent = `Failed to load: ${err instanceof Error ? err.message : String(err)}`;
  }
}

async function loadExamples(): Promise<void> {
  try {
    setStatus("Fetching example list from Haskell server...");

    const response = await fetch("/api/examples");
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`);
    }

    const examples: string[] = await response.json();
    setStatus(`Found ${examples.length} examples. Loading...`, "info");

    // Create cards for all examples
    examplesContainer.innerHTML = "";
    for (const name of examples) {
      const card = createExampleCard(name);
      examplesContainer.appendChild(card);
    }

    // Load SVGs and Canvas diagrams in parallel
    await Promise.all([
      ...examples.map(loadSvgForExample),
      ...examples.map(loadCanvasForExample),
    ]);

    setStatus(`Loaded ${examples.length} examples successfully!`, "success");
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    setStatus(
      `Error: ${message}. Make sure the Haskell server is running on port 8080.`,
      "error",
    );

    // Show fallback message
    examplesContainer.innerHTML = `
      <div class="example-card">
        <div class="example-header">Server Not Available</div>
        <div class="example-content">
          <div class="example-pane svg-pane" style="grid-column: span 2;">
            <div class="placeholder-text">
              <p><strong>Haskell server is not running</strong></p>
              <p>Start the server with: <code>cabal run diagrams-canvas-json</code></p>
              <p>The server should be available at http://localhost:8080</p>
            </div>
          </div>
        </div>
      </div>
    `;
  }
}

loadExamples();
