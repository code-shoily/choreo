defmodule Choreo.JSONTest do
  use ExUnit.Case, async: true

  test "encode!/2 emits valid JSON for Choreo render metadata" do
    encoded =
      Choreo.JSON.encode!(%{
        theme: "base",
        themeVariables: %{
          actorBkg: "#ffffff",
          enabled: true,
          retries: 3,
          missing: nil,
          labels: ["one", "two"]
        }
      })

    assert {:ok, decoded} = Jason.decode(encoded)
    assert decoded["theme"] == "base"
    assert decoded["themeVariables"]["actorBkg"] == "#ffffff"
    assert decoded["themeVariables"]["enabled"] == true
    assert decoded["themeVariables"]["retries"] == 3
    assert decoded["themeVariables"]["missing"] == nil
    assert decoded["themeVariables"]["labels"] == ["one", "two"]
  end
end
