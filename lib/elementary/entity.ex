defmodule Elementary.Entity do
  @moduledoc false

  use Elementary.Provider
  alias(Elementary.{Kit, Ast})

  defstruct rank: :medium,
            name: nil,
            plural: nil,
            version: "1",
            tags: [],
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
        providers
      ) do
    with {:ok, attributes} <- parse_attributes(spec),
         {:ok, relations} <- parse_relations(spec),
         {:ok, plural} <- parse_plural(spec, String.to_atom("#{name}s")),
         entity <- %__MODULE__{
           name: String.to_atom(name),
           version: version,
           attributes: attributes,
           relations: relations,
           plural: plural,
           tags: parse_tags(Map.get(spec, "tags", []))
         },
         {:ok, decoder} <- decoder_spec(entity, providers),
         {:ok, encoder} <- encoder_spec(entity, providers) do
      {:ok, [entity, decoder, encoder]}
    end
  end

  def parse(spec, _), do: Kit.error(:not_supported, spec)

  def decoder_spec(entity, providers) do
    %{
      "kind" => "module",
      "version" => "1",
      "name" => "#{entity.name}_decoder",
      "spec" => %{
        "init" => %{},
        "decoders" => %{
          "http" => %{
            "default" => decoder(entity)
          }
        },
        "update" => %{},
        "encoders" => %{}
      }
    }
    |> Elementary.Module.parse(providers)
  end

  def decoder(entity) do
    Map.merge(
      Enum.reject(entity.attributes, fn attr ->
        attr.name == :id
      end)
      |> Enum.reduce(%{}, fn attr, spec ->
        Map.put(spec, attr.name, %{"any" => decoder_type(attr.type)})
      end),
      Enum.reduce(entity.relations, %{}, fn rel, spec ->
        Map.put(spec, rel.name, %{"any" => "text"})
      end)
    )
  end

  def decoder_type(:id), do: "text"
  def decoder_type(:string), do: "text"
  def decoder_type(:integer), do: "number"

  def encoder_spec(entity, providers) do
    %{
      "kind" => "module",
      "version" => "1",
      "name" => "#{entity.name}_encoder",
      "spec" => %{
        "init" => %{},
        "decoders" => %{},
        "update" => %{},
        "encoders" => %{}
      }
    }
    |> Elementary.Module.parse(providers)
  end

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

  defp parse_plural(%{"plural" => plural}, _) do
    {:ok, String.to_atom(plural)}
  end

  defp parse_plural(_, default) do
    {:ok, default}
  end

  def ast(entity, _) do
    [
      {:module, entity_module(entity),
       [
         {:usage, Elementary.Entity,
          [
            entity: entity
          ]},
         {:fun, :kind, [], :entity},
         {:fun, :name, [], entity.name},
         {:fun, :plural, [], entity.plural},
         {:fun, :tags, [], entity.tags}
       ]},
      {:module, http_handler(entity.name),
       [
         {:usage, Elementary.Entity.Http,
          [
            entity: entity
          ]},
         {:fun, :kind, [], :handler},
         {:fun, :name, [], entity.name}
       ]}
    ]
  end

  defmacro __using__(opts) do
    entity = opts[:entity]

    key =
      entity
      |> Elementary.Entity.key_attributes()
      |> Enum.map(fn attr -> attr.name end)

    quote do
      @module unquote(Elementary.Module.module_name(entity.name))
      @log :log
      @view unquote(entity.plural)

      def get(store, id) do
        store.first(@view, %{id: id})
      end

      def list(store, query, opts \\ []) do
        store.all(@view, query, opts)
      end

      def create(store, %{"id" => id, "version" => v} = view) do
        doc = Map.merge(view, %{"time" => Elementary.Kit.now(), "node" => Node.self()})

        store.write([
          {:insert, @log, doc},
          {:update, @view, %{"id" => id}, view}
        ])
      end

      def delete(store, %{"id" => id, "version" => v} = query) do
        doc =
          Map.merge(query, %{
            "deleted" => true,
            "time" => Elementary.Kit.now(),
            "node" => Node.self()
          })

        store.write([
          {:insert, @log, doc},
          {:delete, @view, query}
        ])
      end

      def init(store) do
        :ok = store.collection(@view)
        :ok = store.index(@view, :pkey, [:id])

        case unquote(key) do
          [] ->
            :ok

          _ ->
            :ok = store.index(@view, :name, unquote(key))
        end
      end
    end
  end

  defmodule Http do
    defmacro __using__(opts) do
      alias Elementary.Entity

      entity = opts[:entity]
      mod = Entity.entity_module(entity)
      decoder_mod = Module.concat([Kit.camelize([entity.name, :decoder, :module])])
      app_mod = Module.concat([Kit.camelize([entity.name, :app])])

      quote do
        use Elementary.App
        use Elementary.Http.Rest
        alias Elementary.Index.Store, as: Store

        def fetch(id, app, _settings) do
          {:ok, store} = Store.get(app)
          unquote(mod).get(store, id)
        end

        def list(filter, opts, app, settings) do
          {:ok, store} = Store.get(app)
          unquote(mod).list(store, filter, opts)
        end

        def create(id, version, body, app, settings) do
          case unquote(decoder_mod).decode(:http, body, settings) do
            {:ok, _, data} ->
              {:ok, store} = Store.get(app)
              data = Map.merge(data, %{"id" => id, "version" => version})

              with :ok <-
                     unquote(mod).create(
                       store,
                       data
                     ) do
                update(unquote(app_mod), "created", data, settings)
              end

            {:error, e} ->
              {:error, :invalid}
          end
        end

        def delete(id, version, app, _settings) do
          {:ok, store} = Store.get(app)

          with {:ok, _} <- unquote(mod).delete(store, %{"id" => id, "version" => version}) do
            {:ok, %{}}
          end
        end
      end
    end
  end

  def http_handler(entity_name) do
    Module.concat([
      Kit.camelize([
        entity_name,
        "http",
        "handler"
      ])
    ])
  end

  def entity_module(e) do
    Module.concat([
      Kit.camelize([
        e.name,
        "entity"
      ])
    ])
  end

  def entity_decoder_module(e) do
    Module.concat([
      Kit.camelize([
        e.name,
        "decoder"
      ])
    ])
  end

  def entity_encoder_module(e) do
    Module.concat([
      Kit.camelize([
        e.name,
        "encoder"
      ])
    ])
  end

  def indexed(mods) do
    Ast.index(mods, Elementary.Index.Entity, :entity)
    |> Ast.compiled()

    Ast.index(mods, Elementary.Index.EntityView, :view)
    |> Ast.compiled()
  end

  use Elementary.Effect, name: :entity

  @entities Elementary.Index.Entity

  def handle_call(%{"in" => store, "first" => entity, "where" => where} = q) do
    with {:ok, entity} <- @entities.get(entity) do
      case entity.list(store, where) do
        {:ok, [item]} ->
          {:ok, item}

        {:ok, []} ->
          {:ok, %{"status" => "not_found", "query" => q}}
      end
    end
  end
end
