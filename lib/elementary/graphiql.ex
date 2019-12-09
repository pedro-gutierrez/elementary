defmodule Elementary.Graphiql do
  @moduledoc false

  use Elementary.Provider

  alias Elementary.Kit

  defstruct path: "/"

  def parse(%{"graphiql" => path}, _) do
    {:ok, %__MODULE__{path: path}}
  end

  def parse(spec, _) do
    Kit.error(:not_supported, spec)
  end

  def ast(spec, _) do
    {:ok,
     {:text,
      """
      <!DOCTYPE html><html><head><link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/graphiql/0.15.1/graphiql.css" /><script src="https://cdnjs.cloudflare.com/ajax/libs/fetch/1.1.0/fetch.min.js"></script><script src="https://cdnjs.cloudflare.com/ajax/libs/react/15.5.4/react.min.js"></script><script src="https://cdnjs.cloudflare.com/ajax/libs/react/15.5.4/react-dom.min.js"></script><script src="https://cdnjs.cloudflare.com/ajax/libs/graphiql/0.15.1/graphiql.js"></script></head><body style="width: 100%; height: 100%; margin: 0; overflow: hidden;"><div id="graphiql" style="height: 100vh;">Loading...</div><script>function graphQLFetcher(graphQLParams) {return fetch("#{
        spec.path
      }", {method: "post",body: JSON.stringify(graphQLParams),credentials: "include",}).then(function (response) {return response.text();}).then(function (responseBody) {try {return JSON.parse(responseBody);} catch (error) {return responseBody;}});}ReactDOM.render(React.createElement(GraphiQL, {fetcher: graphQLFetcher}),document.getElementById("graphiql"));</script></body></html>
      """}}
  end

  def literal?(_), do: true
end
