defmodule Elementary.MixProject do
  use Mix.Project

  def project do
    [
      app: :elementary,
      version: "0.1.0",
      elixir: "~> 1.9.1",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Elementary.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:file_system, "~> 0.2.7"},
      {:yaml_elixir, "~> 2.4.0"},
      {:cowboy, "~> 2.6.3"},
      {:jason, "~> 1.1.2"},
      {:gen_state_machine, ">= 2.0.5"},
      {:absinthe, "~> 1.4"}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
