defmodule Aigifmaker.MixProject do
  use Mix.Project

  def project do
    [
      app: :aigifmaker,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Official SDK for AI GIF Maker (aigifmaker.ai): turn text into animated GIFs.",
      package: package(),
      docs: [main: "readme", extras: ["README.md"]],
      source_url: "https://github.com/hanshs474/aigifmaker-ex",
      homepage_url: "https://aigifmaker.ai/?utm_source=hex&utm_medium=package"
    ]
  end

  def application do
    [extra_applications: [:logger, :inets, :ssl, :public_key, :crypto]]
  end

  defp deps do
    [{:ex_doc, "~> 0.34", only: :dev, runtime: false}]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "Website" => "https://aigifmaker.ai/?utm_source=hex&utm_medium=package",
        "GitHub" => "https://github.com/hanshs474/aigifmaker-ex"
      },
      files: ~w(lib mix.exs README.md LICENSE)
    ]
  end
end
