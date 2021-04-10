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
    notify(%{channel: channel, title: title, severity: "default", doc: doc})
  end

  def notify_async(data) do
    spawn(fn ->
      notify(data)
    end)

    :ok
  end

  def notify(%{channel: channel, severity: sev, title: title} = spec) do
    doc = spec[:doc]

    case Index.spec("settings", "slack") do
      {:ok, %{"spec" => spec}} ->
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

            body = %{
              "attachments" => [
                %{
                  "color" => sev,
                  "text" => text
                }
              ]
            }

            Elementary.Http.Client.run(
              method: "post",
              url: url,
              body: body,
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

      :not_found ->
        Logger.warn("No slack settings. Won't notify on #{channel}")
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
