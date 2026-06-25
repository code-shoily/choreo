if Code.ensure_loaded?(Kino) do
  defmodule Choreo.Lab.Sketch do
    @moduledoc """
    A custom Kino widget that renders Mermaid diagrams inside an interactive Excalidraw whiteboard.

    > #### Experimental module {: .warning}
    > This module is experimental and its API is subject to change.
    """
    use Kino.JS

    @type t :: Kino.JS.t()

    @doc """
    Creates a new Kino widget rendering a Mermaid diagram on an Excalidraw canvas.

    ## Options

      * `:height` - The height of the canvas container (e.g., `"600px"`, `"800px"`). Defaults to `"600px"`.

    """
    @spec new(String.t(), keyword()) :: t()
    def new(mermaid_code, opts \\ []) do
      height = Keyword.get(opts, :height, "600px")
      Kino.JS.new(__MODULE__, %{code: mermaid_code, height: height})
    end

    asset "main.js" do
      """
      function loadScript(src) {
        return new Promise((resolve, reject) => {
          const exists = document.querySelector(`script[src="${src}"]`);
          if (exists) {
            resolve();
            return;
          }
          const script = document.createElement("script");
          script.src = src;
          script.crossOrigin = "anonymous";
          script.onload = () => resolve();
          script.onerror = () => reject(new Error(`Failed to load script: ${src}`));
          document.head.appendChild(script);
        });
      }

      export async function init(ctx, data) {
        ctx.importCSS("main.css");

        // Inject Excalidraw CSS
        const link = document.createElement("link");
        link.rel = "stylesheet";
        link.href = "https://unpkg.com/@excalidraw/excalidraw@0.17.6/dist/excalidraw.min.css";
        document.head.appendChild(link);

        // Add container style
        const container = document.createElement("div");
        container.className = "sketch-container";
        container.style.width = "100%";
        container.style.boxSizing = "border-box";
        container.style.border = "1px solid #e2e8f0";
        container.style.borderRadius = "8px";
        container.style.overflow = "hidden";
        
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
        ctx.root.appendChild(container);

        // Render Loading message
        container.innerHTML = `
          <div style="display: flex; align-items: center; justify-content: center; height: 100%; font-family: system-ui; color: #64748b; background: #f8fafc;">
            <div style="text-align: center;">
              <div style="margin-bottom: 8px; font-weight: 500;">Loading Excalidraw editor...</div>
              <div style="font-size: 13px; color: #94a3b8;">Importing React & Excalidraw assets</div>
            </div>
          </div>
        `;

        try {
          // Load React and ReactDOM first (required by Excalidraw UMD)
          await loadScript("https://unpkg.com/react@18.2.0/umd/react.production.min.js");
          await loadScript("https://unpkg.com/react-dom@18.2.0/umd/react-dom.production.min.js");
          
          // Load Excalidraw UMD library
          await loadScript("https://unpkg.com/@excalidraw/excalidraw@0.17.6/dist/excalidraw.production.min.js");

          // Dynamically import the Mermaid to Excalidraw parser
          const { parseMermaidToExcalidraw } = await import("https://esm.sh/@excalidraw/mermaid-to-excalidraw@2.2.2");

          // Preprocess Mermaid code to make it Excalidraw friendly
          // Specifically handles C4 model diagrams and custom styles which crash or clutter the parser
          const preprocessMermaid = (code) => {
            const lines = code.split("\\n");
            const cleanLines = [];
            for (let line of lines) {
              const trimmed = line.trim();
              
              // Skip style definitions, class definitions, and link styles to keep the diagram clean & hand-drawn
              if (
                trimmed.startsWith("style ") ||
                trimmed.startsWith("classDef ") ||
                trimmed.startsWith("class ") ||
                trimmed.startsWith("linkStyle ")
              ) {
                continue;
              }
              
              // Normalize custom shapes that are not well supported by Excalidraw:
              // Stadium ([label]) -> Rounded Rect (label)
              line = line.replace(/(\\w+)\\(\\[([^\\]]+)\\]\\)/g, '$1($2)');
              
              // Subroutine [[label]] -> Rect [label]
              line = line.replace(/(\\w+)\\[\\[([^\\]]+)\\]\\]/g, '$1[$2]');
              
              // Person/Double circle (((label))) -> Circle ((label))
              line = line.replace(/(\\w+)\\(\\(\\(([^)]+)\\)\\)\\)/g, '$1(($2))');
              
              cleanLines.push(line);
            }
            return cleanLines.join("\\n");
          };

          const cleanCode = preprocessMermaid(data.code);

          // Clear loading text
          container.innerHTML = "";

          // Parse Mermaid syntax to Excalidraw skeleton, then convert to elements using UMD lib
          const { elements, files } = await parseMermaidToExcalidraw(cleanCode, {
            themeVariables: { fontSize: "16px" }
          });
          
          const excalidrawElements = window.ExcalidrawLib.convertToExcalidrawElements(elements);
          const ExcalidrawComponent = window.ExcalidrawLib.Excalidraw;

          const App = () => {
            return React.createElement(
              "div",
              { style: { width: "100%", height: "100%", position: "relative" } },
              React.createElement(ExcalidrawComponent, {
                initialData: {
                  elements: excalidrawElements,
                  appState: { 
                    viewBackgroundColor: "#FAF9F6",
                    gridSize: 20
                  },
                  files: files
                },
                renderTopRightUI: () => {
                  return React.createElement("button", {
                    onClick: () => {
                      if (document.fullscreenElement || document.webkitFullscreenElement) {
                        const exit = document.exitFullscreen || document.webkitExitFullscreen;
                        if (exit) exit.call(document).catch(() => {});
                      } else {
                        const req = container.requestFullscreen || container.webkitRequestFullscreen;
                        if (req) {
                          req.call(container).catch(() => {});
                        }
                      }
                    },
                    title: "Toggle Fullscreen",
                    style: {
                      display: "flex",
                      alignItems: "center",
                      justifyContent: "center",
                      width: "36px",
                      height: "36px",
                      border: "1px solid var(--border-color, #cbd5e1)",
                      borderRadius: "6px",
                      background: "var(--button-bg, #ffffff)",
                      color: "var(--button-color, #334155)",
                      fontSize: "18px",
                      fontWeight: "bold",
                      cursor: "pointer",
                      boxShadow: "0 1px 2px rgba(0,0,0,0.05)",
                      marginRight: "8px"
                    }
                  }, "⛶");
                }
              })
            );
          };

          const root = ReactDOM.createRoot(container);
          root.render(React.createElement(App));
        } catch (error) {
          console.error("Failed to initialize Excalidraw Sketch component:", error);
          container.innerHTML = `
            <div style="padding: 16px; background: #fef2f2; color: #991b1b; font-family: monospace; height: 100%; overflow: auto; box-sizing: border-box;">
              <h3 style="margin-top: 0;">Excalidraw Import/Parse Error</h3>
              <pre style="margin: 0; white-space: pre-wrap;">${error.message || error}</pre>
            </div>
          `;
        }
      }
      """
    end

    asset "main.css" do
      """
      body {
        margin: 0 !important;
        padding: 0 !important;
      }

      .sketch-container {
        position: relative;
      }

      /* Fullscreen overrides */
      .sketch-container:fullscreen {
        width: 100vw !important;
        height: 100vh !important;
        border: none !important;
        border-radius: 0 !important;
      }
      """
    end
  end
end
