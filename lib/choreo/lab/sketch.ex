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
        return new Promise(function(resolve, reject) {
          const exists = document.querySelector(`script[src="${src}"]`);
          if (exists) {
            resolve();
            return;
          }
          const script = document.createElement("script");
          script.src = src;
          script.crossOrigin = "anonymous";
          script.onload = function() { resolve(); };
          script.onerror = function() { reject(new Error(`Failed to load script: ${src}`)); };
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
        const updateHeight = function() {
          if (Math.max(window.innerHeight, defaultHeightNum + 11) === window.innerHeight) {
            container.style.height = "100%";
          } else {
            container.style.height = `${defaultHeightNum}px`;
          }
        };
        updateHeight();
        window.addEventListener("resize", updateHeight);
        ctx.root.appendChild(container);

        // Prevent default spacebar scrolling when interacting with Excalidraw unless typing
        container.addEventListener("keydown", function(e) {
          if (e.key === " " || e.code === "Space") {
            const active = document.activeElement;
            const isInput = active && (
              active.tagName === "INPUT" ||
              active.tagName === "TEXTAREA" ||
              active.contentEditable === "true" ||
              active.closest("[contenteditable='true']")
            );
            if (!isInput) {
              e.preventDefault();
            }
          }
        }, { capture: true });

        // Render Loading message using tag-free DOM creation
        const loadingEl = document.createElement("div");
        loadingEl.style.display = "flex";
        loadingEl.style.alignItems = "center";
        loadingEl.style.justifyContent = "center";
        loadingEl.style.height = "100%";
        loadingEl.style.fontFamily = "system-ui";
        loadingEl.style.color = "#64748b";
        loadingEl.style.background = "#f8fafc";
        const loadingInner = document.createElement("div");
        loadingInner.style.textAlign = "center";
        const loadingTitle = document.createElement("div");
        loadingTitle.style.marginBottom = "8px";
        loadingTitle.style.fontWeight = "500";
        loadingTitle.textContent = "Loading Excalidraw editor...";
        const loadingSubtitle = document.createElement("div");
        loadingSubtitle.style.fontSize = "13px";
        loadingSubtitle.style.color = "#94a3b8";
        loadingSubtitle.textContent = "Importing React & Excalidraw assets";
        loadingInner.appendChild(loadingTitle);
        loadingInner.appendChild(loadingSubtitle);
        loadingEl.appendChild(loadingInner);
        container.appendChild(loadingEl);

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
          const preprocessMermaid = function(code) {
            const lines = code.split("\\n");
            const cleanLines = [];
            for (let line of lines) {
              const trimmed = line.trim();
              
              // Skip style definitions, class definitions, subgraphs, and link styles to keep the diagram clean & hand-drawn
              if (
                trimmed.startsWith("style ") ||
                trimmed.startsWith("classDef ") ||
                trimmed.startsWith("class ") ||
                trimmed.startsWith("linkStyle ") ||
                trimmed.toLowerCase().startsWith("subgraph") ||
                trimmed.toLowerCase() === "end"
              ) {
                continue;
              }
              
              // Normalize custom shapes that are not well supported by Excalidraw:
              // Stadium ([label]) to Rounded Rect (label)
              line = line.replace(/(\\w+)\\(\\[([^\\]]+)\\]\\)/g, '$1($2)');
              
              // Subroutine [[label]] to Rect [label]
              line = line.replace(/(\\w+)\\[\\[([^\\]]+)\\]\\]/g, '$1[$2]');
              
              // Person/Double circle (((label))) to Circle ((label))
              line = line.replace(/(\\w+)\\(\\(\\(([^)]+)\\)\\)\\)/g, '$1(($2))');

              // Cylinder/Database shape with double quotes [("label")] to Rect ["label"]
              line = line.replace(/(\\w+)\\[\\(\\"(.*?)\\"\\)\\]/g, '$1["$2"]');
              // Cylinder/Database shape without double quotes [(label)] to Rect [label]
              line = line.replace(/(\\w+)\\[\\((.*?)\\)\\]/g, '$1[$2]');

              // Parallelograms [/"label"\] and [/label\] to Rect
              line = line.replace(/(\\w+)\\[\\/\\"(.*?)\\"\\\\\\]/g, '$1["$2"]');
              line = line.replace(/(\\w+)\\[\\/([^\]]+)\\\\\\]/g, '$1[$2]');

              // Parallelograms [\"label"/] and [\label/] to Rect
              line = line.replace(/(\\w+)\\[\\\\\\"(.*?)\\"\\/\\]/g, '$1["$2"]');
              line = line.replace(/(\\w+)\\[\\\\([^\]]+)\\/\\]/g, '$1[$2]');

              // Replace HTML line breaks <br> / <br/> with newlines so Excalidraw parses them as multi-line labels
              line = line.replace(new RegExp("\\\\x3cbr\\\\\\\\s*\\\\\\\\/?\\\\x3e", "gi"), "\\\\n");
              
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

          const App = function() {
            const [excalidrawAPI, setExcalidrawAPI] = React.useState(null);

            React.useEffect(function() {
              if (excalidrawAPI) {
                setTimeout(function() {
                  excalidrawAPI.scrollToContent();
                }, 100);
              }
            }, [excalidrawAPI]);

            return React.createElement(
              "div",
              { style: { width: "100%", height: "100%", position: "relative" } },
              React.createElement(ExcalidrawComponent, {
                excalidrawAPI: function(api) { setExcalidrawAPI(api); },
                initialData: {
                  elements: excalidrawElements,
                  scrollToContent: true,
                  appState: { 
                    viewBackgroundColor: "#FAF9F6",
                    gridSize: 20
                  },
                  files: files
                },
                renderTopRightUI: function() {
                  return React.createElement("button", {
                    onClick: function() {
                      if (document.fullscreenElement || document.webkitFullscreenElement) {
                        const exit = document.exitFullscreen || document.webkitExitFullscreen;
                        if (exit) exit.call(document).catch(function() {});
                      } else {
                        const req = container.requestFullscreen || container.webkitRequestFullscreen;
                        if (req) {
                          req.call(container).catch(function() {});
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
          container.innerHTML = "";
          const errorEl = document.createElement("div");
          errorEl.style.padding = "16px";
          errorEl.style.background = "#fef2f2";
          errorEl.style.color = "#991b1b";
          errorEl.style.fontFamily = "monospace";
          errorEl.style.height = "100%";
          errorEl.style.overflow = "auto";
          errorEl.style.boxSizing = "border-box";
          const errorTitle = document.createElement("h3");
          errorTitle.style.marginTop = "0";
          errorTitle.textContent = "Excalidraw Import/Parse Error";
          const errorPre = document.createElement("pre");
          errorPre.style.margin = "0";
          errorPre.style.whiteSpace = "pre-wrap";
          errorPre.textContent = error.message || error;
          errorEl.appendChild(errorTitle);
          errorEl.appendChild(errorPre);
          container.appendChild(errorEl);
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
