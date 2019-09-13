defmodule Elementary.Provider do
  @moduledoc false

  @callback parse(map(), list(map())) :: {:ok, map()} | {:error, any()}
  @callback ast(map(), list(tuple())) :: list(tuple()) | tuple()

  defmacro __using__(opts) do
    if opts[:kind] do
      quote do
        @behaviour Elementary.Provider
        def module(), do: unquote(opts)[:module]
        def kind(), do: unquote(opts)[:kind]
      end
    else
      quote do
        def module(), do: unquote(opts)[:module]
      end
    end
  end
end
