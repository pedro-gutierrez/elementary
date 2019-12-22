defmodule Elementary.Effect do
  @moduledoc false

  @callback call(map()) :: {:ok, term()} | {:error, term()}

  defmacro __using__(opts) do
    quote do
      @behaviour Elementary.Effect
      def kind(), do: :effect
      def name(), do: unquote(opts[:name])

      def call(data) do
        handle_call(data)
      end
    end
  end

  alias Elementary.Ast

  def indexed(mods) do
    mods
    |> Ast.index(Elementary.Index.Effect)
    |> Ast.compiled()
  end
end
