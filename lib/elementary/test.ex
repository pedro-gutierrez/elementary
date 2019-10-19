defmodule Elementary.Test do
  @moduledoc false
  alias Elementary.Index.{Settings}

  def run(_test, settings, _owner) do
    case Settings.get(settings) do
      {:ok, _settings} ->
        :ok

      {:error, :not_found} ->
        {:error, {:not_found, settings}}
    end
  end
end
