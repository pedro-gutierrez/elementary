defmodule Elementary.Graph do
  @moduledoc false

  use Elementary.Provider
  alias(Elementary.{Kit})

  defstruct rank: :high,
            name: "",
            version: "1",
            store: nil,
            settings: [],
            entities: []

  defmodule Entity do
    alias Elementary.Graph.Attribute

    defstruct name: nil,
              plural: nil,
              attributes: [],
              relations: []

    def key_attributes(%__MODULE__{} = e) do
      e.attributes
      |> Enum.filter(fn attr ->
        Attribute.is(attr, :key)
      end)
    end
  end

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
        %{"version" => version, "kind" => "graph", "name" => name, "spec" => spec},
        _
      ) do
    settings =
      case spec do
        %{"settings" => settings} ->
          [name | settings]

        _ ->
          [name]
      end

    with {:ok, entities} <- parse_entities(spec),
         {:ok, store} <- parse_store(spec) do
      {:ok,
       %__MODULE__{
         name: name,
         version: version,
         settings: Enum.uniq(settings),
         entities: entities,
         store: store
       }}
    end
  end

  def parse(spec, _), do: Kit.error(:not_supported, spec)

  def parse_store(%{"store" => store}) do
    {:ok, String.to_atom(store)}
  end

  def parse_store(spec) do
    {:error, %{spec: spec, reason: :missing_store}}
  end

  def parse_entities(%{"entities" => entities}) do
    Enum.reduce_while(entities, [], fn {name, spec}, acc ->
      case parse_entity(name, spec) do
        {:ok, e} ->
          {:cont, [e | acc]}

        {:error, _} = e ->
          {:halt, e}
      end
    end)
    |> case do
      {:error, e} ->
        Kit.error(:parse_error, %{
          kind: :graph,
          reason: e
        })

      entities when is_list(entities) ->
        {:ok, Enum.reverse(entities)}
    end
  end

  defp parse_entity(name, spec) do
    with {:ok, attrs} <- parse_attributes(spec),
         {:ok, rels} <- parse_relations(spec) do
      {:ok,
       %Entity{
         name: String.to_atom(name),
         plural: String.to_atom("#{name}s"),
         attributes: attrs,
         relations: rels
       }}
    end
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
    with [_ | _] = rels <-
           Enum.reduce_while(rels, [], fn {name, spec}, rels ->
             case parse_relation(spec) do
               {:ok, rel} ->
                 {:cont, [Relation.with_name(rel, name) | rels]}

               {:error, _} = error ->
                 {:halt, error}
             end
           end) do
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

  def ast(graph, _) do
    asts = [
      {
        :module,
        Kit.camelize([graph.name, "Graph"]),
        [
          {:usage, [:Absinthe, :Schema]},
          {:fun, :kind, [], :graph},
          {:fun, :name, [], {:symbol, graph.name}}
        ] ++
          [op_type()] ++
          types(graph.entities) ++
          [
            {:block, :query, {:props, [name: "Query"]}, queries(graph.entities)},
            {:block, :mutation, {:props, [name: "Mutation"]}, mutations(graph)}
          ]
      }
    ]

    asts
  end

  defp types(entities) do
    Enum.map(entities, fn e ->
      type_for_entity(e, entities)
    end)
  end

  defp queries(entities) do
    Enum.flat_map(entities, fn e ->
      queries_for_entity(e, entities)
    end)
  end

  defp mutations(graph) do
    Enum.flat_map(graph.entities, fn e ->
      mutations_for_entity(e, graph)
    end)
  end

  defp type_for_entity(e, all) do
    {:block, :object, e.name,
     List.flatten([
       attribute_fields_for_entity(e, all),
       relation_fields_for_entity(e, all)
     ])}
  end

  defp op_type() do
    {:block, :object, :op,
     [
       {:call, :field, [:ref, :id]}
     ]}
  end

  defp attribute_fields_for_entity(e, _all) do
    Enum.map(e.attributes, fn attr ->
      {:call, :field, [attr.name, attr.type]}
    end)
  end

  defp relation_fields_for_entity(e, _all) do
    e.relations
    |> Enum.filter(&Relation.is(&1, :belongs))
    |> Enum.map(fn rel ->
      {:call, :field, [rel.name, {:call, :non_null, [rel.entity]}]}
    end)
  end

  defp queries_for_entity(e, all) do
    [
      query_for_entity_list(e, all),
      e
      |> Entity.key_attributes()
      |> Enum.map(fn attr ->
        query_for_single_by_attribute(e, attr, all)
      end),
      query_for_single_by_attribute(e, Attribute.id(), all),
      queries_for_multiple_by_relations(e, all)
    ]
  end

  defp query_for_single_by_attribute(e, attr, _all) do
    {:block, :field, [Kit.atom_from([e.name, :by, attr.name]), e.name],
     [
       arg_from_attribute(attr),
       {:call, :resolve,
        [
          {:lambda, [:_, :_, :_], {:ok, {:map, []}}}
        ]}
     ]}
  end

  defp query_for_entity_list(e, _all) do
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

  defp queries_for_multiple_by_relations(e, all) do
    e.relations
    |> Enum.filter(&Relation.is(&1, :belongs))
    |> Enum.map(&query_for_multiple_by_relation(e, &1, all))
  end

  defp query_for_multiple_by_relation(e, rel, _all) do
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

  defp mutations_for_entity(e, graph) do
    [
      create_mutation(e, graph),
      update_mutation(e, graph),
      delete_mutation(e, graph)
    ]
  end

  defp create_mutation(e, graph) do
    store_name = Elementary.Store.store_name(graph.store)

    {:block, :field, [Kit.atom_from([:create, e.name]), :op],
     create_args_for_entity(e, graph) ++
       [
         {:call, :resolve,
          [
            mutation_ast(store_name, e.name, :create)
          ]}
       ]}
  end

  defp update_mutation(e, graph) do
    store_name = Elementary.Store.store_name(graph.store)

    {:block, :field, [Kit.atom_from([:update, e.name]), :op],
     update_args_for_entity(e, graph) ++
       [
         {:call, :resolve,
          [
            mutation_ast(store_name, e.name, :update)
          ]}
       ]}
  end

  defp delete_mutation(e, graph) do
    store_name = Elementary.Store.store_name(graph.store)

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
          {:call, store, :write,
           [
             {:map,
              [
                {:kind, entity_name},
                {:event, event},
                {:data, {:var, :params}}
              ]}
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

  defp create_args_for_entity(e, all) do
    args_for_entity(e, all)
  end

  defp update_args_for_entity(e, all) do
    args_for_entity(e, all)
  end

  defp args_for_entity(e, _all) do
    List.flatten([
      Enum.map(e.attributes, &arg_from_attribute(&1)),
      e.relations
      |> Enum.filter(&Relation.is(&1, :belongs))
      |> Enum.map(&arg_from_relation(&1))
    ])
  end

  def indexed(mods) do
    {:module, Elementary.Index.Graph,
     (mods
      |> Enum.filter(fn m ->
        m.kind() == :graph
      end)
      |> Enum.flat_map(fn m ->
        res = {:tuple, [:ok, m]}

        [
          {:fun, :get, [{:symbol, m.name()}], res},
          {:fun, :get, [{:text, m.name()}], res}
        ]
      end)) ++
       [
         {:fun, :get, [{:var, :_}], {:tuple, [:error, :not_found]}}
       ]}
    |> Elementary.Ast.compiled()
  end
end
