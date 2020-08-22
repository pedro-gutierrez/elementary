defmodule Elementary.Slack do
  require Logger
  alias Elementary.Index

  def notify_async(channel, title, doc \\ nil) do
    spawn(fn ->
      notify(channel, title, doc)
    end)

    :ok
  end

  def notify(channel, title, doc \\ nil) do
    %{"spec" => spec} = Index.spec!("settings", "slack")

    case spec[channel] do
      nil ->
        Logger.warn("No webhook configured for slack channel \"#{channel}\"")
        :error

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
        |> case do
          %{"status" => 200, "body" => "ok"} ->
            :ok

          _ ->
            :error
        end
    end
  end

  defp code(doc) do
    case Jason.encode(doc, pretty: true) do
      {:ok, json} ->
        "```#{json}```"

      _ ->
        "Error encoding JSON"
    end
  end
end
