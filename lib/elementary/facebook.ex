defmodule Elementary.Facebook do
  alias Elementary.Http

  def resolve_event(id) do
    with {:ok, %{"status" => code, "body" => html}} <-
           Http.Client.run(url: "https://www.facebook.com/events/#{id}") do
      case code do
        200 ->
          with {:ok, event} <- parse_event(html) do
            {:ok, Map.put(event, "id", id)}
          end

        404 ->
          {:error, "no_such_event"}
      end
    else
      {:ok, %{"error" => e}} ->
        {:error, e}
    end
  end

  def parse_event(html) do
    html =
      html
      |> String.replace("<!--", "<commented>")
      |> String.replace("-->", "</commented>")

    {:ok, doc} = Floki.parse_document(html)

    event =
      doc
      |> event_from_json()
      |> event_with_cover(doc)
      |> event_with_title_fallback(doc)
      |> event_with_start_date_fallback(doc)
      |> event_with_place_fallback(doc)
      |> event_with_related_events(doc)

    case has_values(event, ["cover", "title", "starts", "place"]) do
      true ->
        {:ok, event}

      false ->
        {:error, :no_such_event}
    end
  end

  defp event_from_json(doc) do
    with {_, _, [script]} <-
           doc |> Floki.find("script[type=\"application/ld+json\"]") |> Enum.at(0),
         {:ok, %{"image" => cover, "name" => name, "startDate" => starts, "url" => url} = json} <-
           Jason.decode(script),
         {:ok, starts, _} <- DateTime.from_iso8601(starts) do
      %{"cover" => cover, "title" => name, "starts" => starts, "url" => url}
      |> event_with_postal_address(json)
    else
      _ ->
        %{}
    end
  end

  defp event_with_postal_address(event, %{
         "location" => %{
           "address" => %{
             "addressCountry" => country,
             "addressLocality" => area,
             "postalCode" => zip,
             "streetAddress" => street
           }
         }
       }) do
    Map.merge(event, %{"country" => country, "area" => area, "zip" => zip, "street" => street})
  end

  defp event_with_postal_address(event, _), do: event

  defp event_with_cover(event, doc) do
    cover =
      doc
      |> Floki.find("#event_header_primary img")
      |> Floki.attribute("src")
      |> Enum.at(0)

    Map.put(event, "cover", cover)
  end

  defp event_with_title_fallback(event, doc) do
    case event["title"] do
      nil ->
        title =
          doc
          |> Floki.find("h1[data-testid=\"event-permalink-event-name\"]")
          |> Floki.text()

        Map.put(event, "title", title)

      _ ->
        event
    end
  end

  defp event_with_start_date_fallback(event, doc) do
    case event["starts"] do
      nil ->
        case doc
             |> Floki.find("#event_time_info div[content]")
             |> Floki.attribute("content") do
          [] ->
            event

          [starts | _] ->
            starts =
              starts
              |> String.split(" to ")
              |> Enum.at(0)

            {:ok, starts, _} = DateTime.from_iso8601(starts)

            Map.put(event, "starts", starts)
        end

      _ ->
        event
    end
  end

  defp event_with_place_fallback(event, doc) do
    case event["place"] do
      nil ->
        case doc
             |> Floki.find("commented ul li table a") do
          [] ->
            event

          [place | _] ->
            place = Floki.text(place)
            Map.put(event, "place", place)
        end

      _ ->
        event
    end
  end

  defp event_with_related_events(event, doc) do
    related =
      doc
      |> Floki.find(".fbEventsSuggestionItem a")
      |> Floki.attribute("href")
      |> Enum.filter(&String.contains?(&1, "events"))
      |> Enum.map(fn url ->
        url |> String.split("/") |> Enum.at(2)
      end)
      |> Enum.uniq()

    Map.put(event, "related", related)
  end

  defp has_values(_, []), do: true

  defp has_values(event, [key | rest]) do
    case event[key] do
      nil ->
        false

      _ ->
        has_values(event, rest)
    end
  end
end
