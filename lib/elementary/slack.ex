defmodule Elementary.Slack do
  require Logger
  alias Elementary.Index

  def notify(channel, title, doc \\ nil) do
    %{"spec" => spec} = Index.spec!("settings", "slack")

    case spec[channel] do
      nil ->
        Logger.warn("No webhook configured for slack channel \"#{channel}\"")

      url ->
        text =
          case doc do
            nil ->
              title

            _ ->
              "#{title} #{code(doc)}"
          end

        Elementary.Http.Client.run(
          method: "post",
          url: url,
          body: %{
            "text" => text
          },
          headers: %{
            "content-type" => "application/json"
          }
        )
    end
  end

  defp code(doc) do
    case Jason.encode(doc) do
      {:ok, json} ->
        "```#{json}```"

      _ ->
        "Error encoding JSON"
    end
  end
end
