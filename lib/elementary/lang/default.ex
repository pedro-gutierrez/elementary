defmodule Elementary.Lang.Default do
  @moduledoc false

  use Elementary.Provider,
    module: __MODULE__

  alias Elementary.Kit

  def parse(spec, providers) when is_map(spec) do
    Kit.parse_spec(
      %{
        "dict" => spec
      },
      providers
    )
  end

  def parse(spec, _) do
    Kit.error(:not_supported, spec)
  end
end
