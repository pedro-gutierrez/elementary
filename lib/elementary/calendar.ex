defmodule Elementary.Calendar do
  @moduledoc false

  def now() do
    {:ok, DateTime.utc_now()}
  end

  def today() do
    date = DateTime.utc_now()

    {:ok,
     %{
       date
       | hour: 0,
         minute: 0,
         second: 0,
         time_zone: "Europe/London",
         zone_abbr: "UTC",
         std_offset: 0,
         utc_offset: 0
     }}
  end

  def date(%DateTime{} = date), do: {:ok, date}

  def date(%{"day" => day, "month" => month, "year" => year}) do
    {:ok, date} = today()
    {:ok, %{date | year: year, month: month, day: day}}
  end

  def date(%{"month" => _, "year" => _} = spec) do
    spec
    |> Map.put("day", 1)
    |> date()
  end

  def date(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, date, _} ->
        {:ok, date}

      _ = res ->
        {:error, %{"error" => "date", "date" => res}}
    end
  end

  def format_date(datetime, pattern) do
    {:ok, NimbleStrftime.format(datetime, pattern)}
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
  def day(%DateTime{day: day}), do: {:ok, day}

  def duration_between(to, from) do
    seconds = DateTime.diff(to, from)
    {days, {hours, minutes, seconds}} = :calendar.seconds_to_daystime(seconds)
    %{"days" => days, "hours" => hours, "minutes" => minutes, "seconds" => seconds}
  end

  def time_in(amount, :hour) do
    {:ok, DateTime.utc_now() |> DateTime.add(3600 * amount, :second)}
  end

  def time_in(amount, :month) do
    {:ok, DateTime.utc_now() |> DateTime.add(3600 * 24 * 30 * amount, :second)}
  end

  def time_ago(amount, :hour) do
    {:ok, DateTime.utc_now() |> DateTime.add(-3600 * amount, :second)}
  end

  def time_ago(amount, :month) do
    {:ok, DateTime.utc_now() |> DateTime.add(-3600 * 24 * 30 * amount, :second)}
  end

  def time_ago(amount, :second) do
    {:ok, DateTime.utc_now() |> DateTime.add(-amount, :second)}
  end
end
