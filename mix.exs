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
        :mongodb_driver,
        :ranch,
        :httpoison
      ],
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
      {:uuid, "~> 1.1"},
      {:argon2_elixir, "~> 2.0"},
      {:mongodb_driver, "~> 0.6"},
      {:httpoison, "~> 1.6"}
    ]
  end
end
