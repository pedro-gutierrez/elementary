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

  def decode(mod, effect, data, model) do
    debug(mod, effect: effect, data: data, model: model)

    case mod.decode(effect, data, model) do
      {:ok, event, decoded} ->
        debug(mod, decoded: event, data: decoded)
        update(mod, event, decoded, model)

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

  def maybe_update(mod, event, data, model0) do
    case Elementary.Kit.module_defined?(mod) do
      true ->
        case update(mod, event, data, model0) do
          {:error, :no_update} ->
            {:ok, data}

          other ->
            other
        end

      false ->
        {:ok, data}
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
