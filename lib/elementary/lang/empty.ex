defmodule Elementary.Lang.Empty do
  @moduledoc false

  use Elementary.Provider,
    kind: "empty",
    module: __MODULE__

  alias Elementary.Kit

  def parse(%{"empty" => "list"}, providers) do
    Kit.parse_spec(
      %{
        "list" => "empty"
      },
      providers
    )
  end

  def parse(spec, _) do
    Kit.error(:not_supported, spec)
  end
end
