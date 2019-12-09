defmodule Elementary.Mount do
  @moduledoc false

  defstruct app: "", path: "", protocol: "http"

  def parse(mounts) do
    {:ok,
     Enum.flat_map(mounts, fn {app, app_mounts} ->
       Enum.map(app_mounts, fn {protocol, path} ->
         %__MODULE__{
           app: app,
           protocol: protocol,
           path: path
         }
       end)
     end)
     |> Enum.reverse()}
  end
end
