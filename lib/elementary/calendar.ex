defmodule Elementary.Calendar do
  @moduledoc false

  def date(%DateTime{} = date), do: {:ok, date}

  def date(%{"day" => day, "month" => month, "year" => year}) do
    {:ok,
     %DateTime{
       year: year,
       month: month,
       day: day,
       hour: 0,
       minute: 0,
       second: 0,
       time_zone: "Europe/London",
       zone_abbr: "UTC",
       std_offset: 0,
       utc_offset: 0
     }}
  end

  def date(%{"month" => _, "year" => _} = spec) do
    spec
    |> Map.put("day", 1)
    |> date()
  end

  def format_date(fields) do
    with {:ok, date} <- date(fields) do
      {:ok, DateTime.to_iso8601(date)}
    end
  end

  def first_dom(date), do: {:ok, %{date | day: 1, hour: 0, minute: 0, second: 0}}

  def last_dom(date) do
    {:ok,
     %{
       date
       | day: Date.days_in_month(date),
         hour: 23,
         minute: 59,
         second: 59
     }}
  end

  def month(%DateTime{month: month}), do: {:ok, month}
  def year(%DateTime{year: year}), do: {:ok, year}

  def time_in(amount, :hour) do
    {:ok, DateTime.utc_now() |> DateTime.add(3600 * amount, :second)}
  end

  def time_in(amount, :month) do
    {:ok, DateTime.utc_now() |> DateTime.add(3600 * 24 * 30 * amount, :second)}
  end
end
