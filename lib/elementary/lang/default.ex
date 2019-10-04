defmodule Elementary.Lang.Default do
  @moduledoc false

  use Elementary.Provider,
    kind: :default,
    module: __MODULE__,
    rank: :lowest

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
