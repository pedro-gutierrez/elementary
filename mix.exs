defmodule Elementary.MixProject do
  use Mix.Project

  def project do
    [
      app: :elementary,
      version: "0.1.0",
      elixir: "~> 1.10.1",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      applications: [
        :argon2_elixir,
        :cowboy,
        :file_system,
        :httpoison,
        :jason,
        :mongodb_driver,
        :ranch,
        :uuid,
        :yaml_elixir
      ],
      mod: {Elementary.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:argon2_elixir, "~> 2.0"},
      {:cowboy, "~> 2.6.3"},
      {:file_system, "~> 0.2.7"},
      {:httpoison, "~> 1.6"},
      {:jason, "~> 1.1.2"},
      {:mongodb_driver, "~> 0.6"},
      {:uuid, "~> 1.1"},
      {:yaml_elixir, "~> 2.4.0"}
    ]
  end
end
