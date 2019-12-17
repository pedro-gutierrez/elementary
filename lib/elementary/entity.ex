defmodule Elementary.Entity do
  @moduledoc false

  use Elementary.Provider
  alias(Elementary.{Kit, Ast})

  defstruct rank: :medium,
            name: nil,
            plural: nil,
            version: "1",
            graph: nil,
            attributes: [],
            relations: []

  defmodule Attribute do
    defstruct name: nil,
              type: nil,
              tags: []

    def id(), do: %__MODULE__{name: :id, type: :id}

    def is(%__MODULE__{} = attr, tag) do
      Enum.member?(attr.tags, tag)
    end
  end

  defmodule Relation do
    defstruct name: nil,
              entity: nil,
              tags: []

    def is(%__MODULE__{} = rel, tag) do
      Enum.member?(rel.tags, tag)
    end

    def with_name(%__MODULE__{entity: nil} = rel, name) do
      name = String.to_atom(name)
      %__MODULE__{rel | entity: name, name: name}
    end

    def with_name(%__MODULE__{} = rel, name) do
      name = String.to_atom(name)
      %__MODULE__{rel | name: name}
    end
  end

  def parse(
        %{"version" => version, "kind" => "entity", "name" => name, "spec" => spec},
        _
      ) do
    with {:ok, attributes} <- parse_attributes(spec),
         {:ok, graph} <- parse_graph(spec),
         {:ok, relations} <- parse_relations(spec),
         {:ok, plural} <- parse_plural(spec, String.to_atom("#{name}s")) do
      {:ok,
       %__MODULE__{
         name: String.to_atom(name),
         version: version,
         graph: graph,
         attributes: attributes,
         relations: relations,
         plural: plural
       }}
    end
  end

  def parse(spec, _), do: Kit.error(:not_supported, spec)

  def key_attributes(%__MODULE__{} = e) do
    e.attributes
    |> Enum.filter(fn attr ->
      Attribute.is(attr, :key)
    end)
  end

  defp parse_attributes(%{"attributes" => attrs}) do
    with [_ | _] = attrs <-
           Enum.reduce_while(attrs, [], fn {name, spec}, attrs ->
             case parse_attribute(spec) do
               {:ok, attr} ->
                 {:cont, [%Attribute{attr | name: String.to_atom(name)} | attrs]}

               {:error, _} = error ->
                 {:halt, error}
             end
           end) do
      {:ok, [Attribute.id() | Enum.reverse(attrs)]}
    end
  end

  defp parse_attributes(_), do: {:ok, [Attribute.id()]}

  defp parse_attribute(kind) when is_binary(kind) do
    {:ok,
     %Attribute{
       type: String.to_atom(kind)
     }}
  end

  defp parse_attribute(%{"kind" => kind, "tags" => tags}) do
    {:ok,
     %Attribute{
       type: String.to_atom(kind),
       tags: parse_tags(tags)
     }}
  end

  defp parse_attribute(%{"kind" => kind}) do
    parse_attribute(%{"kind" => kind, "tags" => []})
  end

  defp parse_tags(list) when is_list(list) do
    Enum.map(list, &String.to_atom(&1))
  end

  defp parse_tags(str) when is_binary(str) do
    str
    |> String.split(",")
    |> Enum.map(&String.trim(&1))
    |> parse_tags()
  end

  defp parse_relations(%{"relations" => rels}) do
    Enum.reduce_while(rels, [], fn {name, spec}, rels ->
      case parse_relation(spec) do
        {:ok, rel} ->
          {:cont, [Relation.with_name(rel, name) | rels]}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:error, _} = e ->
        e

      rels ->
        {:ok, Enum.reverse(rels)}
    end
  end

  defp parse_relations(_) do
    {:ok, []}
  end

  defp parse_relation(%{"entity" => entity, "tags" => tags}) do
    {:ok,
     %Relation{
       entity: String.to_atom(entity),
       tags: parse_tags(tags)
     }}
  end

  defp parse_relation(%{"tags" => tags}) do
    {:ok,
     %Relation{
       tags: parse_tags(tags)
     }}
  end

  defp parse_graph(%{"graph" => graph}) do
    {:ok, String.to_atom(graph)}
  end

  defp parse_graph(spec) do
    {:error, %{reason: :mssing_graph, spec: spec}}
  end

  defp parse_plural(%{"plural" => plural}, _) do
    {:ok, String.to_atom(plural)}
  end

  defp parse_plural(_, default) do
    {:ok, default}
  end

  def ast(entity, _) do
    mod = module(entity.name)

    [
      {:module, mod,
       [
         {:usage, Elementary.Entity,
          [
            entity: entity.name,
            graph: entity.graph
          ]},
         {:fun, :graph, [], entity.graph},
         {:fun, :kind, [], :entity},
         {:fun, :name, [], entity.name}
       ]},
      {:module, types(entity.name),
       [
         {:usage, [:Absinthe, :Schema, :Notation]},
         {:fun, :kind, [], :types},
         {:fun, :name, [], {:symbol, entity.name}},
         type_for_entity(entity),
         {:block, :object, queries(entity.name), queries_for_entity(entity)},
         {:block, :object, mutations(entity.name), mutations_for_entity(entity)}
       ]}
    ]
  end

  def activate(kind, id) do
    with {:ok, mod} = Elementary.Index.Entity.get(kind) do
      Elementary.Apps.launch(mod, id)
    end
  end

  def update(pid, data) do
    GenStateMachine.cast(pid, {:update, data})
  end

  defmacro __using__(opts) do
    quote do
      @entity unquote(opts[:entity])
      @module unquote(Elementary.Module.module_name(opts[:entity]))
      @graph unquote(opts[:graph])
      @store unquote(Elementary.Store.store_name(opts[:graph]))

      require Logger

      use GenStateMachine, callback_mode: :state_functions

      def start_link(_owner, id) do
        GenStateMachine.start_link(__MODULE__, id, name: {:via, Registry, {Apps, {@entity, id}}})
      end

      defstruct id: nil, model: %{}

      @impl true
      def init(id) do
        # at some stage the init phase should involve
        # reconstructing the state for the entity by reading the last
        # snapshots + latest events from the store
        {:ok, :ready, %__MODULE__{id: id}}
      end

      def ready(:cast, {:update, data}, state) do
        with {:ok, model, events} <- handle(data, state.model) do
          Enum.each(events, fn e ->
            {:ok, _} = @store.write(e)
          end)

          {:keep_state, %{state | model: model}}
        else
          e ->
            Logger.error("#{inspect(e)}")
            {:stop, :shutdown, nil}
        end
      end

      defp handle(%{"event" => e, "data" => data} = event, model) do
        case update(e, data, model) do
          :no_update ->
            # There is no user defined policy for the given incoming
            # event. Check whether we have a default, built-in event
            case default_event(event) do
              {:ok, event} ->
                # Emit the default event produced by the entity
                # for the incoming event
                {:ok, data, [event]}

              :ignore ->
                # No user defined, and no built-in event
                Logger.warn(
                  "#{
                    inspect(
                      entity: @entity,
                      process: __MODULE__,
                      module: @module,
                      ignored: event
                    )
                  }"
                )

                {:ok, data, []}
            end

          {:ok, m2, []} ->
            # The user-defined policy simply aggregates the state,
            # but does not emit new events
            {:ok, Map.merge(model, m2), []}

          {:ok, m2, [encoder: _enc]} ->
            # The user defined policy produces a new aggregated state
            # and also emits new events
            {:ok, Map.merge(model, m2), []}
        end
      end

      def update(e, data, model) do
        case Elementary.Kit.module_defined?(@module) do
          false ->
            :no_update

          true ->
            case @module.update(e, data, model) do
              {:error, :no_update} ->
                :no_update

              other ->
                other
            end
        end
      end

      defp handle(data, model) do
        IO.inspect(ignored: data, model: model)
        {:ok, model, []}
      end

      defp default_event(%{"event" => e} = event) do
        with {:ok, e} <- event_for(e) do
          {:ok, Map.put(event, "event", e)}
        end
      end

      defp event_for("create"), do: {:ok, "created"}
      defp event_for("update"), do: {:ok, "updated"}
      defp event_for("delete"), do: {:ok, "deleted"}
      defp event_for(_), do: :ignore

      @impl true
      def terminate(reason, state, data) do
        Logger.warn(
          "#{
            inspect(
              store: @store,
              module: @module,
              terminated: reason,
              state: state,
              data: data
            )
          }"
        )
      end
    end
  end

  def module(e) do
    Module.concat([
      Kit.camelize([
        e,
        "entity"
      ])
    ])
  end

  def types(e) do
    Module.concat([
      Kit.camelize([
        e,
        "types"
      ])
    ])
  end

  def queries(e) do
    String.to_atom("#{e}_queries")
  end

  def mutations(e) do
    String.to_atom("#{e}_mutations")
  end

  def indexed(mods) do
    Ast.index(mods, Elementary.Index.Entity, :entity)
    |> Ast.compiled()
  end

  defp type_for_entity(e) do
    {:block, :object, e.name,
     List.flatten([
       attribute_fields_for_entity(e),
       relation_fields_for_entity(e)
     ])}
  end

  defp attribute_fields_for_entity(e) do
    Enum.map(e.attributes, fn attr ->
      {:call, :field, [attr.name, attr.type]}
    end)
  end

  defp relation_fields_for_entity(e) do
    e.relations
    |> Enum.filter(&Relation.is(&1, :belongs))
    |> Enum.map(fn rel ->
      {:call, :field, [rel.name, {:call, :non_null, [rel.entity]}]}
    end)
  end

  defp queries_for_entity(e) do
    [
      query_for_entity_list(e),
      e
      |> key_attributes()
      |> Enum.map(fn attr ->
        query_for_single_by_attribute(e, attr)
      end),
      query_for_single_by_attribute(e, Attribute.id()),
      queries_for_multiple_by_relations(e)
    ]
  end

  defp query_for_single_by_attribute(e, attr) do
    {:block, :field, [Kit.atom_from([e.name, :by, attr.name]), e.name],
     [
       arg_from_attribute(attr),
       {:call, :resolve,
        [
          {:lambda, [:_, :_, :_], {:ok, {:map, []}}}
        ]}
     ]}
  end

  defp query_for_entity_list(e) do
    {:block, :field, [e.plural, {:call, :list_of, [e.name]}],
     [
       limit_arg(),
       offset_arg(),
       {:call, :resolve,
        [
          {:lambda, [:_, :_, :_], {:ok, []}}
        ]}
     ]}
  end

  defp queries_for_multiple_by_relations(e) do
    e.relations
    |> Enum.filter(&Relation.is(&1, :belongs))
    |> Enum.map(&query_for_multiple_by_relation(e, &1))
  end

  defp query_for_multiple_by_relation(e, rel) do
    name = Kit.atom_from([e.plural, :by, rel.name])

    {:block, :field, [name, {:call, :list_of, [e.name]}],
     [
       arg_from_relation(rel),
       limit_arg(),
       offset_arg(),
       {:call, :resolve,
        [
          {:lambda, [:_, :_, :_], {:ok, []}}
        ]}
     ]}
  end

  defp mutations_for_entity(e) do
    [
      create_mutation(e),
      update_mutation(e),
      delete_mutation(e)
    ]
  end

  defp create_mutation(e) do
    store_name = Elementary.Store.store_name(e.graph)

    {:block, :field, [Kit.atom_from([:create, e.name]), :op],
     create_args_for_entity(e) ++
       [
         {:call, :resolve,
          [
            mutation_ast(store_name, e.name, :create)
          ]}
       ]}
  end

  defp update_mutation(e) do
    store_name = Elementary.Store.store_name(e.graph)

    {:block, :field, [Kit.atom_from([:update, e.name]), :op],
     update_args_for_entity(e) ++
       [
         {:call, :resolve,
          [
            mutation_ast(store_name, e.name, :update)
          ]}
       ]}
  end

  defp delete_mutation(e) do
    store_name = Elementary.Store.store_name(e.graph)

    {:block, :field, [Kit.atom_from([:delete, e.name]), :op],
     [
       arg_from_attribute(Attribute.id()),
       {:call, :resolve,
        [
          mutation_ast(store_name, e.name, :delete)
        ]}
     ]}
  end

  defp mutation_ast(store, entity_name, event) do
    {:lambda, [:_, :params, :_],
     {:let,
      [
        id:
          {:call, store, :write_command,
           [
             entity_name,
             event,
             {:var, :params}
           ]}
      ], {:ok, {:map, [ref: {:var, :id}]}}}}
  end

  defp arg_from_attribute(attr) do
    {:call, :arg, [attr.name, {:call, :non_null, [attr.type]}]}
  end

  defp arg_from_relation(rel) do
    {:call, :arg, [rel.name, {:call, :non_null, [:id]}]}
  end

  defp limit_arg() do
    {:call, :arg, [:limit, :integer]}
  end

  defp offset_arg() do
    {:call, :arg, [:offset, :integer]}
  end

  defp create_args_for_entity(e) do
    args_for_entity(e)
  end

  defp update_args_for_entity(e) do
    args_for_entity(e)
  end

  defp args_for_entity(e) do
    List.flatten([
      Enum.map(e.attributes, &arg_from_attribute(&1)),
      e.relations
      |> Enum.filter(&Relation.is(&1, :belongs))
      |> Enum.map(&arg_from_relation(&1))
    ])
  end
end
