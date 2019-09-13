defmodule Elementary.Lang.Default do
  @moduledoc false

  use Elementary.Provider,
    module: __MODULE__

  alias Elementary.Kit

  defstruct spec: %{}

  def parse(spec, providers) when is_binary(spec) do
    Kit.parse_spec(
      %{
        "text" => spec
      },
      providers
    )
  end

  def parse(spec, providers) when is_number(spec) do
    Kit.parse_spec(
      %{
        "number" => spec
      },
      providers
    )
  end

  def parse(spec, providers) when is_boolean(spec) do
    Kit.parse_spec(
      %{
        "boolean" => spec
      },
      providers
    )
  end

  def parse(spec, providers) when is_map(spec) do
    Kit.parse_spec(
      %{
        "dict" => spec
      },
      providers
    )
  end

  def parse(spec, providers) when is_list(spec) do
    Kit.parse_spec(
      %{
        "list" => spec
      },
      providers
    )
  end

  def compile(_, _), do: []
end
