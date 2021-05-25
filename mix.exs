defmodule LoggerSplunkBackend.Mixfile do
  use Mix.Project

  def project do
    [
      app: :logger_splunk_backend,
      version: "3.0.0",
      elixir: "~> 1.9",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: [
        plt_add_deps: :app_tree
      ],
      test_coverage: [tool: LcovEx]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:httpoison, "~> 1.6"},
      {:jason, "~> 1.1"},
      {:bypass, "~> 2.0", optional: true, only: [:test]},
      {:cowlib, "~> 1.0.2", optional: true, only: [:test]},
      {:lcov_ex, "~> 0.2", only: :test, optional: true},
      {:credo, "~> 1.5", only: :dev, optional: true},
      {:dialyxir, "~> 1.1", only: :dev, optional: true}
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description do
    """
    A Logger backend to support the Splunk service
    (splunk.com) HTTP Event Collector (HEC)log mechanism
    """
  end

  defp package do
    [
      files: ["config", "lib", "mix.exs", "README*", "LICENSE*", "CHANGELOG*"],
      maintainers: ["MBTA"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/mbta/logger_splunk_backend"}
    ]
  end
end
