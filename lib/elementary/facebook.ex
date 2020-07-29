defmodule Elementary.Facebook do
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

    {:ok, event}
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
        starts =
          doc
          |> Floki.find("#event_time_info div[content]")
          |> Floki.attribute("content")
          |> Enum.at(0)
          |> String.split(" to ")
          |> Enum.at(0)

        {:ok, starts, _} = DateTime.from_iso8601(starts)

        Map.put(event, "starts", starts)

      _ ->
        event
    end
  end

  defp event_with_place_fallback(event, doc) do
    case event["place"] do
      nil ->
        place =
          doc
          |> Floki.find("commented ul li table a")
          |> Enum.at(0)
          |> Floki.text()

        Map.put(event, "place", place)

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
end
