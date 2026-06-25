if Code.ensure_loaded?(Kino) do
  defmodule Choreo.Lab.Siren do
    @moduledoc """
    A custom Kino widget for rendering Mermaid diagrams with pan, zoom, and height control.

    > #### Experimental module {: .warning}
    > This module is experimental and its API is subject to change.
    """
    use Kino.JS

    @type t :: Kino.JS.t()

    @doc """
    Creates a new Kino widget displaying the given Mermaid diagram.

    ## Options

      * `:height` - The height of the widget container (e.g., `"400px"`, `"600px"`, `500`). Defaults to `"400px"`.
      * `:theme` - The Mermaid theme to use (e.g., `"default"`, `"dark"`, `"forest"`, `"neutral"`).
        If not set, it will auto-detect based on the environment's background brightness.

    """
    @spec new(String.t(), keyword()) :: t()
    def new(mermaid_code, opts \\ []) do
      height = Keyword.get(opts, :height, "400px")
      theme = Keyword.get(opts, :theme)
      Kino.JS.new(__MODULE__, %{code: mermaid_code, height: height, theme: theme})
    end

    asset "main.js" do
      """
      import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs";

      export async function init(ctx, data) {
        ctx.importCSS("main.css");

        const container = document.createElement("div");
        container.className = "siren-container";
        
        const defaultHeightNum = typeof data.height === 'number' ? data.height : parseInt(data.height) || 400;
        const updateHeight = () => {
          if (window.innerHeight > defaultHeightNum + 10) {
            container.style.height = "100%";
          } else {
            container.style.height = `${defaultHeightNum}px`;
          }
        };
        updateHeight();
        window.addEventListener("resize", updateHeight);

        const viewport = document.createElement("div");
        viewport.className = "siren-viewport";
        container.appendChild(viewport);

        ctx.root.appendChild(container);

        // Helper text overlay that fades out
        const helper = document.createElement("div");
        helper.className = "siren-helper";
        helper.innerText = "Drag to pan • Scroll to zoom";
        container.appendChild(helper);

        const dismissHelper = () => {
          helper.classList.add("siren-helper-hidden");
          setTimeout(() => helper.remove(), 500);
        };
        setTimeout(dismissHelper, 3000);

        // Floating controls
        const controls = document.createElement("div");
        controls.className = "siren-controls";

        const btnZoomIn = document.createElement("button");
        btnZoomIn.innerHTML = "＋";
        btnZoomIn.title = "Zoom In";
        
        const btnZoomOut = document.createElement("button");
        btnZoomOut.innerHTML = "－";
        btnZoomOut.title = "Zoom Out";

        const btnFit = document.createElement("button");
        btnFit.innerHTML = "⛶";
        btnFit.title = "Fit Screen";

        const btnReset = document.createElement("button");
        btnReset.innerHTML = "↺";
        btnReset.title = "Reset View";

        controls.appendChild(btnZoomIn);
        controls.appendChild(btnZoomOut);
        controls.appendChild(btnFit);
        controls.appendChild(btnReset);
        container.appendChild(controls);

        // Auto-detect theme if not explicitly provided
        let theme = data.theme;
        if (!theme) {
          const bg = window.getComputedStyle(document.body).backgroundColor;
          const rgb = bg.match(/\\d+/g);
          if (rgb && rgb.length >= 3) {
            const brightness = (parseInt(rgb[0]) * 299 + parseInt(rgb[1]) * 587 + parseInt(rgb[2]) * 114) / 1000;
            theme = brightness < 128 ? 'dark' : 'default';
          } else {
            theme = 'default';
          }
        }

        mermaid.initialize({
          startOnLoad: false,
          securityLevel: 'loose',
          theme: theme
        });

        const renderId = "siren-" + Math.random().toString(36).substring(2, 9);
        let svgElement = null;

        let scale = 1.0;
        let translateX = 0;
        let translateY = 0;
        let isPanning = false;
        let startX = 0;
        let startY = 0;

        const updateTransform = () => {
          viewport.style.transform = `translate(${translateX}px, ${translateY}px) scale(${scale})`;
        };

        const resetView = () => {
          scale = 1.0;
          translateX = 0;
          translateY = 0;
          updateTransform();
        };

        const fitView = () => {
          if (!svgElement) return;
          const viewBoxAttr = svgElement.getAttribute('viewBox');
          if (viewBoxAttr) {
            const [vx, vy, vw, vh] = viewBoxAttr.split(' ').map(Number);
            const rect = container.getBoundingClientRect();
            const cw = rect.width;
            const ch = rect.height;

            if (cw === 0 || ch === 0) return;

            const scaleX = (cw * 0.95) / vw;
            const scaleY = (ch * 0.95) / vh;
            // Cap scale at 2.0 to prevent tiny diagrams from blowing up
            scale = Math.min(scaleX, scaleY, 2.0);

            translateX = (cw - vw * scale) / 2;
            translateY = (ch - vh * scale) / 2;
            updateTransform();
          } else {
            resetView();
          }
        };

        try {
          const { svg } = await mermaid.render(renderId, data.code);
          viewport.innerHTML = svg;
          svgElement = viewport.querySelector("svg");
          
          if (svgElement) {
            svgElement.removeAttribute("width");
            svgElement.removeAttribute("height");
            svgElement.style.width = "100%";
            svgElement.style.height = "100%";
            svgElement.style.maxWidth = "none";
            svgElement.style.display = "block";
            
            // Set viewport size explicitly to SVG dimensions to avoid double scaling
            const viewBoxAttr = svgElement.getAttribute('viewBox');
            if (viewBoxAttr) {
              const [vx, vy, vw, vh] = viewBoxAttr.split(' ').map(Number);
              viewport.style.width = `${vw}px`;
              viewport.style.height = `${vh}px`;
            }
            
            fitView();
          }
        } catch (error) {
          console.error("Mermaid rendering error:", error);
          container.innerHTML = `<div class="siren-error"><h3>Mermaid Render Error</h3><pre>${error.message || error}</pre></div>`;
          return;
        }

        // Fit view dynamically when container resizes
        const resizeObserver = new ResizeObserver((entries) => {
          for (let entry of entries) {
            if (entry.contentRect.width > 0 && entry.contentRect.height > 0) {
              fitView();
            }
          }
        });
        resizeObserver.observe(container);

        document.addEventListener('fullscreenchange', fitView);
        document.addEventListener('webkitfullscreenchange', fitView);

        // Interaction handlers: Pan
        container.addEventListener('mousedown', (e) => {
          if (e.target.closest('.siren-controls')) return;
          isPanning = true;
          container.classList.add('siren-grabbing');
          startX = e.clientX - translateX;
          startY = e.clientY - translateY;
          dismissHelper();
        });

        window.addEventListener('mousemove', (e) => {
          if (!isPanning) return;
          translateX = e.clientX - startX;
          translateY = e.clientY - startY;
          updateTransform();
        });

        window.addEventListener('mouseup', () => {
          if (isPanning) {
            isPanning = false;
            container.classList.remove('siren-grabbing');
          }
        });

        container.addEventListener('mouseleave', () => {
          if (isPanning) {
            isPanning = false;
            container.classList.remove('siren-grabbing');
          }
        });

        // Interaction handlers: Zoom
        container.addEventListener('wheel', (e) => {
          if (e.target.closest('.siren-controls')) return;
          e.preventDefault();
          dismissHelper();

          const zoomFactor = 1.1;
          let newScale = e.deltaY < 0 ? scale * zoomFactor : scale / zoomFactor;
          newScale = Math.max(0.1, Math.min(10, newScale));

          const rect = container.getBoundingClientRect();
          const mouseX = e.clientX - rect.left;
          const mouseY = e.clientY - rect.top;

          translateX = mouseX - (mouseX - translateX) * (newScale / scale);
          translateY = mouseY - (mouseY - translateY) * (newScale / scale);
          scale = newScale;

          updateTransform();
        }, { passive: false });

        btnZoomIn.addEventListener('click', () => {
          dismissHelper();
          const rect = container.getBoundingClientRect();
          const cx = rect.width / 2;
          const cy = rect.height / 2;
          const newScale = Math.min(10, scale * 1.2);
          
          translateX = cx - (cx - translateX) * (newScale / scale);
          translateY = cy - (cy - translateY) * (newScale / scale);
          scale = newScale;
          updateTransform();
        });

        btnZoomOut.addEventListener('click', () => {
          dismissHelper();
          const rect = container.getBoundingClientRect();
          const cx = rect.width / 2;
          const cy = rect.height / 2;
          const newScale = Math.max(0.1, scale / 1.2);

          translateX = cx - (cx - translateX) * (newScale / scale);
          translateY = cy - (cy - translateY) * (newScale / scale);
          scale = newScale;
          updateTransform();
        });

        btnFit.addEventListener('click', () => {
          dismissHelper();
          if (document.fullscreenElement || document.webkitFullscreenElement) {
            const exit = document.exitFullscreen || document.webkitExitFullscreen;
            if (exit) exit.call(document).catch(() => {});
          } else {
            const req = container.requestFullscreen || container.webkitRequestFullscreen;
            if (req) {
              req.call(container).catch(() => fitView());
            } else {
              fitView();
            }
          }
        });

        btnReset.addEventListener('click', () => {
          dismissHelper();
          resetView();
        });
      }
      """
    end

    asset "main.css" do
      """
      body {
        margin: 0 !important;
        padding: 0 !important;
      }

      .siren-container {
        position: relative;
        width: 100%;
        overflow: hidden;
        border: 1px solid #e2e8f0;
        border-radius: 8px;
        background-color: #f8fafc;
        user-select: none;
        cursor: grab;
        box-sizing: border-box;
      }

      .siren-container.siren-grabbing {
        cursor: grabbing;
      }

      .siren-viewport {
        position: absolute;
        transform-origin: 0px 0px;
        transition: transform 0.05s ease-out;
      }

      .siren-viewport svg {
        pointer-events: none;
      }

      .siren-controls {
        position: absolute;
        bottom: 12px;
        right: 12px;
        display: flex;
        flex-direction: row;
        gap: 6px;
        background: rgba(255, 255, 255, 0.85);
        backdrop-filter: blur(4px);
        -webkit-backdrop-filter: blur(4px);
        padding: 4px;
        border-radius: 6px;
        border: 1px solid #cbd5e1;
        box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06);
        z-index: 10;
      }

      .theme-dark .siren-controls {
        background: rgba(30, 41, 59, 0.85);
        border-color: #475569;
      }

      .siren-controls button {
        display: flex;
        align-items: center;
        justify-content: center;
        width: 28px;
        height: 28px;
        border: none;
        border-radius: 4px;
        background: #ffffff;
        color: #334155;
        font-size: 14px;
        font-weight: bold;
        cursor: pointer;
        transition: all 0.2s;
        box-shadow: 0 1px 2px rgba(0,0,0,0.05);
      }

      .theme-dark .siren-controls button {
        background: #1e293b;
        color: #e2e8f0;
      }

      .siren-controls button:hover {
        background: #f1f5f9;
        color: #0f172a;
      }

      .theme-dark .siren-controls button:hover {
        background: #334155;
        color: #ffffff;
      }

      .siren-controls button:active {
        transform: scale(0.95);
      }

      .siren-helper {
        position: absolute;
        top: 12px;
        left: 50%;
        transform: translateX(-50%);
        background: rgba(15, 23, 42, 0.75);
        color: #ffffff;
        padding: 6px 12px;
        border-radius: 20px;
        font-size: 12px;
        pointer-events: none;
        transition: opacity 0.5s ease;
        z-index: 10;
        backdrop-filter: blur(4px);
        -webkit-backdrop-filter: blur(4px);
      }

      .siren-helper-hidden {
        opacity: 0;
      }

      .siren-error {
        width: 100%;
        height: 100%;
        padding: 16px;
        overflow: auto;
        background: #fef2f2;
        color: #991b1b;
        font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
      }

      .siren-error h3 {
        margin-top: 0;
        font-size: 16px;
      }

      .siren-error pre {
        margin: 0;
        white-space: pre-wrap;
        font-size: 13px;
      }

      .siren-container:fullscreen {
        width: 100vw !important;
        height: 100vh !important;
        background-color: #f8fafc;
      }

      .theme-dark .siren-container:fullscreen {
        background-color: #0f172a;
      }
      """
    end
  end
end
