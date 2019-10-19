defmodule Elementary.Choose do
  @moduledoc false

  use Elementary.Provider

  alias Elementary.Kit

  defstruct expression: nil, options: [], default: nil

  def parse(%{"choose" => expression, "when" => options, "otherwise" => default}, providers) do
    with {:ok, expr} <- Kit.parse_spec(expression, providers),
         {:ok, options} <- Kit.parse_spec(options, providers),
         {:ok, default} <- Kit.parse_spec(default, providers) do
      {:ok, %__MODULE__{expression: expr, options: options, default: default}}
    else
      e -> e
    end
  end

  def parse(spec, _) do
    Kit.error(:not_supported, spec)
  end

  def ast(parsed, index) do
    {:case, parsed.expression.__struct__.ast(parsed.expression, index),
     Enum.map(parsed.options.spec, fn {condition, expr} ->
       {{:ok, condition}, expr.__struct__.ast(expr, index)}
     end) ++
       [
         {{:ok, {:var, :_}}, parsed.default.__struct__.ast(parsed.default, index)},
         {{:error, {:var, :e}}, {:error, {:var, :e}}}
       ]}
  end
end
