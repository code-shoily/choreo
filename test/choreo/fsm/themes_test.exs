defmodule Choreo.FSM.ThemesTest do
  use ExUnit.Case, async: true

  alias Choreo.FSM.Themes
  alias Choreo.Theme

  describe "resolve/2" do
    test "resolves all predefined themes" do
      for theme_name <- [:default, :dark, :minimal, :warm, :forest, :ocean] do
        theme = Themes.resolve(theme_name)
        assert %Theme{} = theme
      end
    end

    test "resolves with overrides" do
      theme = Themes.resolve(:warm, node_fontsize: 16)
      assert theme.node_fontsize == 16
    end

    test "resolves custom Theme struct with and without overrides" do
      custom = %Theme{name: :custom, node_fontsize: 14}
      assert Themes.resolve(custom, []) == custom

      overridden = Themes.resolve(custom, node_fontsize: 20)
      assert overridden.node_fontsize == 20
    end

    test "resolves unknown theme with fallback to default" do
      theme = Themes.resolve(:unknown_theme, [])
      assert theme.name == :fsm_default
    end
  end
end
