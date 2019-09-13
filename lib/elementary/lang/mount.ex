defmodule Elementary.Lang.Mount do
  @moduledoc false

  defstruct app: "", path: "", protocol: "http"

  def parse(mounts) do
    {:ok,
     mounts
     |> Enum.reduce_while([], fn {app, mounts}, acc ->
       {:cont,
        (acc ++ mounts)
        |> Enum.map(fn {protocol, path} ->
          %__MODULE__{
            app: app,
            protocol: protocol,
            path: path
          }
        end)}
     end)}
  end
end
