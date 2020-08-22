defmodule Elementary.App do
  @moduledoc false
  require Logger
  alias Elementary.{Index, Decoder, Encoder, Effect}

  def run(spec, effect, data) do
    with {:ok, settings} <- settings(spec),
         {:ok, model, _} <- init(spec, settings),
         {:ok, model2} <- filter(spec, effect, data, model) do
      decode_update(
        spec,
        effect,
        data,
        Map.merge(model, model2)
      )
    end
  end

  def settings(%{"spec" => %{"settings" => settings, "encoders" => encoders}}) do
    Encoder.encode(settings, %{}, encoders)
  end

  def settings(%{"spec" => %{"settings" => settings}}) do
    Encoder.encode(settings, %{}, %{})
  end

  def settings(_), do: {:ok, %{}}

  def settings!(spec) do
    case settings(spec) do
      {:ok, settings} ->
        settings

      other ->
        raise "Could not encode settings for spec\n\n#{inspect(spec)}\n\nReason: #{inspect(other)}"
    end
  end

  def init(%{"spec" => %{"init" => init, "encoders" => encoders}}, settings) do
    with {:ok, encoded} <-
           Encoder.encode(
             init,
             settings,
             encoders
           ) do
      %{"model" => model, "cmds" => cmds} = Map.merge(%{"model" => %{}, "cmds" => %{}}, encoded)
      {:ok, Map.merge(settings, model), cmds}
    end
  end

  def filter(%{"spec" => %{"filters" => filters}}, effect, data, model) do
    filters
    |> Enum.reduce_while(model, fn filter, model ->
      case "app" |> Index.spec!(filter) |> decode_update(effect, data, model) do
        {:ok, model} ->
          {:cont, model}

        other ->
          {:halt, other}
      end
    end)
    |> case do
      {:stop, _} = err ->
        err

      {:error, _} = err ->
        err

      model ->
        {:ok, model}
    end
  end

  def filter(_, _, _, model), do: {:ok, model}

  def decode_update(spec, effect, data, model) do
    with {:ok, %{"event" => event, "decoded" => decoded}} <- do_decode(spec, effect, data, model) do
      update(spec, event, decoded, model)
    end
  end

  defp do_decode(%{"spec" => %{"decoders" => decoders}}, effect, data, model) do
    case decoders[effect] do
      nil ->
        {:error, "no_decoder"}

      decoders ->
        decode_first(decoders, data, model)
    end
    |> case do
      {:error, e} ->
        {:error, %{"effect" => effect, "data" => data, "model" => model, "error" => e}}

      decoded ->
        decoded
    end
  end

  defp decode_first(decoders, data, model) do
    Enum.reduce_while(decoders, nil, fn {event, spec}, _ ->
      case Decoder.decode(spec, data, model) do
        {:ok, decoded} ->
          {:halt, %{"event" => event, "decoded" => decoded}}

        {:error, _} ->
          {:cont, nil}
      end
    end)
    |> case do
      nil ->
        {:error, "no_decoder"}

      decoded ->
        {:ok, decoded}
    end
  end

  def update(%{"spec" => %{"update" => update}} = spec, event, data, model0) do
    case update[event] do
      nil ->
        {:error, %{"event" => event, "error" => "no_update"}}

      updates ->
        update_first(spec, updates, %{"data" => data, "model" => model0})
        |> case do
          {:ok, model, cmds} ->
            cmds(spec, cmds, Map.merge(model0, model))

          other ->
            other
        end
    end
  end

  defp update_first(
         %{"spec" => %{"encoders" => encoders}} = spec,
         %{"when" => condition} = update,
         context
       ) do
    case Encoder.encode(condition, context, encoders) do
      {:ok, false} ->
        false

      {:ok, _} ->
        update_first(spec, update, context)

      {:error, _} = error ->
        error
    end
  end

  defp update_first(
         %{"spec" => %{"encoders" => encoders}},
         update,
         %{"model" => model} = context
       ) do
    with {:ok, encoded} <- Encoder.encode(update["model"] || %{}, context, encoders),
         {:ok, cmds} <- Encoder.encode(update["cmds"] || %{}, Map.merge(model, encoded), encoders) do
      {:ok, encoded, cmds}
    else
      {:error, e} ->
        {:error, %{"spec" => update, "reason" => e}}
    end
  end

  defp update_first(spec, [update | rest], context) do
    with false <- update_first(spec, update, context) do
      update_first(spec, rest, context)
    end
  end

  defp update_first(_, [], _), do: false

  def cmds(spec, cmds, model) when is_map(cmds) do
    cmds(spec, Map.to_list(cmds), model)
  end

  def cmds(_, [], model), do: {:ok, model}

  def cmds(spec, [{effect, enc} | rest], model0) do
    case cmd(spec, effect, enc, model0) do
      {:ok, model} ->
        cmds(spec, rest, model)

      other ->
        other
    end
  end

  def cmd(%{"spec" => %{"encoders" => encoders}} = spec, eff, enc, model) do
    with {:ok, encoded} <- Encoder.encode(%{"encoder" => enc}, model, encoders) do
      case eff do
        "return" ->
          {:ok, encoded}

        "stop" ->
          {:stop, encoded}

        _ ->
          effect(spec, eff, encoded, model)
      end
    end
  end

  def effect(spec, eff, encoded, model) do
    with {:ok, data} <- Effect.apply(eff, encoded) do
      decode_update(spec, eff, data, model)
    end
  end
end
