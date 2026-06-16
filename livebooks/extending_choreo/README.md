# Extending Choreo

This directory contains tutorials that teach you how to add new diagram vocabularies to Choreo. Unlike `livebooks/guides/` (which introduce existing modules) and `livebooks/integrations/` (which bridge Choreo with external tools), these notebooks define new Choreo modules inline and explain the extension pattern.

## Notebooks

- [`git_graph.livemd`](./git_graph.livemd) — add a `Choreo.GitGraph` module that renders branch/merge history as a Mermaid `gitGraph`, including a small adapter that reads real `git log` output.

## Pattern

Each notebook follows the same shape:

1. Define a builder module (`lib/choreo/<name>.ex`).
2. Define one or more renderers (`lib/choreo/<name>/render/*.ex`).
3. Write tests/assertions (`test/choreo/<name>_test.exs`).
4. (Optional) Add an adapter that imports real-world data.

The modules are defined inline in the notebook so you can experiment without creating files. When you are ready to ship, extract the code blocks into the file paths shown in each section.
