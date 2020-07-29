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
        :content_type,
        :cowboy,
        :file_system,
        :floki,
        :httpoison,
        :libcluster,
        :jason,
        :mongodb_driver,
        :mustache,
        :nimble_strftime,
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
      {:content_type, "~> 0.1.0"},
      {:cowboy, "~> 2.6.3"},
      {:file_system, "~> 0.2.7"},
      {:floki, "~> 0.27.0"},
      {:httpoison, "~> 1.6"},
      {:jason, "~> 1.1.2"},
      {:libcluster, "~> 3.2"},
      {:mongodb_driver, "~> 0.6"},
      {:mustache, "~> 0.3.0"},
      {:nimble_strftime, "~> 0.1.0"},
      {:uuid, "~> 1.1"},
      {:yaml_elixir, "~> 2.4.0"}
    ]
  end
end
