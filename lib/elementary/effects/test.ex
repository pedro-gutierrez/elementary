defmodule Elementary.Effects.Test do
  @moduledoc false

  use Elementary.Effect, :test

  def effect(owner, %{"run" => %{"settings" => settings, "test" => test}}) do
    case Elementary.Test.run(test, settings, owner) do
      :ok ->
        %{"status" => "running"}

      {:error, {:not_found, e}} ->
        %{"status" => "not_found", "reason" => e}

      {:error, e} ->
        %{"status" => "error", "reason" => e}
    end
    |> update(owner)
  end
end
