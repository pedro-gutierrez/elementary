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
        error([app: mod.name(), phase: :init], e)
    end
  end

  def filter(mod, effect, data, model) do
    res =
      mod.filters
      |> Enum.reduce_while(model, fn filter, model ->
        {next, _} =
          res =
          case decode(filter, effect, data, model) do
            {:ok, model} ->
              {:cont, model}

            other ->
              {:halt, other}
          end

        debug(mod, %{filter: filter.name(), result: next})
        res
      end)
      |> case do
        {:stop, _} = err ->
          err

        {:error, _} = err ->
          err

        model ->
          {:ok, model}
      end

    res
  end

  def decode(mod, effect, data, model) do
    case mod.decode(effect, data, model) do
      {:ok, event, decoded} ->
        debug(mod, %{decode: effect, event: event})

        case update(mod, event, decoded, model) do
          {:ok, _ } = result ->
            #{:ok, Map.merge(model, model2)}
            result

          {:stop, _} = stop ->
            stop

          {:error, e} ->
            error([app: mod.name(), event: event, data: decoded, model: model], e)
        end

      {:error, e} ->
        error([app: mod.name(), effect: effect], e)
    end
  end

  def update(mod, event, data, model0) do
    debug(mod, %{update: event})

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
        error([app: mod.name(), update: event], e)
    end
  end

  def cmd(mod, effect, nil, model) do
    effect(mod, effect, nil, model)
  end

  def cmd(mod, effect, enc, model) do
    res =
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
          error([app: mod.name(), encoder: enc], e)
      end

    debug(mod, %{cmd: %{effect: effect, encoder: enc}})
    res
  end

  def effect(mod, effect, encoded, model) do
    with {:ok, data} <- Elementary.Effect.apply(effect, encoded) do
      decode(mod, effect, data, model)
    else
      {:error, e} ->
        error([app: mod.name(), effect: effect, data: encoded], e)

      other ->
        error([app: mod.name(), effect: effect, data: encoded], %{unexpected: other})
    end
  end

  defp debug(mod, info) do
    Map.merge(info, %{
      kind: mod.kind(),
      name: mod.name()
    })
    |> Elementary.Logger.log()
  end

  defp error(context, e) do
    context = Keyword.take(context, [:app, :event, :data])
    {:error, Keyword.merge(context, error: e) |> Enum.into(%{})}
  end
end
