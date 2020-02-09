defmodule Elementary.App do
  @moduledoc false
  require Logger

  def init(mod, settings) do
    case mod.init(settings) do
      {:ok, model, []} ->
        {:ok, model}

      {:ok, model, [{effect, enc}]} ->
        cmd(mod, effect, enc, model)

      {:error, e} ->
        error([app: mod, phase: :init], e)
    end
  end

  def filter(mod, effect, data, model) do
    mod.filters
    |> Enum.reduce_while(model, fn filter, model ->
      case decode(filter, effect, data, model) do
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

  def decode(mod, effect, data, model) do
    debug(mod, effect: effect, data: data, model: model)

    case mod.decode(effect, data, model) do
      {:ok, event, decoded} ->
        debug(mod, decoded: event, data: decoded)

        case update(mod, event, decoded, model) do
          {:ok, model2} ->
            {:ok, Map.merge(model, model2)}

          {:stop, _} = stop ->
            stop

          {:error, e} ->
            error([app: mod, event: event, data: decoded, model: model], e)
        end

      {:error, e} ->
        error([app: mod, effect: effect], e)
    end
  end

  def update(mod, event, data, model0) do
    debug(mod, event: event, data: data, model: model0)

    case mod.update(event, data, model0) do
      {:ok, model, cmds} when is_map(cmds) and map_size(cmds) == 1 ->
        [{effect, enc}] = Map.to_list(cmds)
        cmd(mod, effect, enc, Map.merge(model0, model))

      {:ok, model, [{effect, enc}]} ->
        cmd(mod, effect, enc, Map.merge(model0, model))

      {:ok, model, [effect]} ->
        cmd(mod, effect, nil, Map.merge(model0, model))

      {:ok, model, []} ->
        {:ok, model}

      {:error, e} ->
        error([app: mod, update: event], e)
    end
  end

  def cmd(mod, effect, nil, model) do
    effect(mod, effect, nil, model)
  end

  def cmd(mod, effect, enc, model) do
    case mod.encode(enc, model) do
      {:ok, encoded} ->
        case effect do
          "return" ->
            {:ok, encoded}

          "stop" ->
            {:stop, encoded}

          _ ->
            effect(mod, effect, encoded, model)
        end

      {:error, e} ->
        error([app: mod, encoder: enc], e)
    end
  end

  def effect(mod, effect, encoded, model) do
    debug(mod, effect: effect, data: encoded, model: model)

    with {:ok, data} <- Elementary.Effect.apply(effect, encoded) do
      decode(mod, effect, data, model)
    else
      {:error, e} ->
        error([app: mod, effect: effect, data: encoded], e)
        {:error, :internal_error}

      other ->
        error([app: mod, effect: effect, data: encoded], %{unexpected: other})
    end
  end

  defp debug(mod, info) do
    case mod.debug() do
      true ->
        Logger.info("#{inspect(info)}")

      false ->
        :ok
    end
  end

  defp error(context, e) do
    Logger.error("#{inspect(Keyword.merge(context, error: e))}")
    {:error, e}
  end
end
