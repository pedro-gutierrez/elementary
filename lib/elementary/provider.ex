defmodule Elementary.Provider do
  @moduledoc false

  @callback parse(map(), list(map())) :: {:ok, map()} | {:error, any()}

  defmacro __using__(opts) do
    quote do
      @behaviour Elementary.Provider
      def rank(), do: unquote(opts[:rank] || :medium)
    end
  end
end
