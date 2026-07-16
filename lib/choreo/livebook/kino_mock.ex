defmodule Choreo.Livebook.KinoMock do
  @moduledoc false

  # Headless stand-ins for Kino modules so Livebook code blocks can be
  # evaluated outside of an actual Livebook runtime.

  defmodule Layout do
    @moduledoc false
    def tabs(opts), do: opts
    def grid(inputs, _opts \\ []), do: inputs
  end

  defmodule Markdown do
    @moduledoc false
    def new(txt), do: txt
  end

  defmodule HTML do
    @moduledoc false
    def new(html), do: html
  end

  defmodule VizJS do
    @moduledoc false
    def render(dot, _opts \\ []), do: dot
  end

  defmodule Mermaid do
    @moduledoc false
    def new(source), do: source
  end

  defmodule Text do
    @moduledoc false
    def new(txt), do: txt
  end

  defmodule DataTable do
    @moduledoc false
    def new(data, _opts \\ []), do: data
  end

  defmodule JS do
    @moduledoc false
    def new(module, data), do: %{module: module, data: data}
  end

  defmodule Input do
    @moduledoc false
    def text(_label, opts \\ []), do: {:input, opts[:default]}
    def password(_label, opts \\ []), do: {:input, opts[:default]}
    def textarea(_label, opts \\ []), do: {:input, opts[:default]}
    def number(_label, opts \\ []), do: {:input, opts[:default]}

    def select(_label, options, opts \\ []) do
      default =
        opts[:default] ||
          (is_list(options) && not Enum.empty?(options) && elem(List.first(options), 0))

      {:input, default}
    end

    def checkbox(_label, opts \\ []), do: {:input, opts[:default]}
    def read({:input, val}), do: val
    def read(val), do: val
  end

  defmodule Control do
    @moduledoc false
    def button(label), do: {:control, label}

    def select(_label, options, opts \\ []) do
      default =
        opts[:default] ||
          (is_list(options) && not Enum.empty?(options) && elem(List.first(options), 0))

      {:control, default}
    end
  end

  defmodule Frame do
    @moduledoc false
    def new, do: {:frame, nil}
    def render(frame, content), do: {frame, content}
  end

  defmodule Image do
    @moduledoc false
    def new(data, _mime_type), do: data
  end

  defmodule Download do
    @moduledoc false
    def new(func, _opts \\ []), do: func
  end

  defmodule Process do
    @moduledoc false
    def render(content), do: content
  end

  # Top-level Kino functions that are not namespaced under a submodule.
  def render(value), do: value
end
