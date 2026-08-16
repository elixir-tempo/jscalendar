defmodule JSCalendar.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :jscalendar,
      version: @version,
      name: "JSCalendar",
      source_url: "https://github.com/elixir-tempo/jscalendar",
      docs: docs(),
      deps: deps(),
      description: description(),
      package: package(),
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      dialyzer: [
        flags: [
          :error_handling,
          :unknown,
          :underspecs,
          :extra_return,
          :missing_return
        ]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def description do
    "JSCalendar (RFC 8984) for Elixir — the JSON representation of " <>
      "calendar data, as events, tasks and groups. No dependencies."
  end

  defp deps do
    [
      {:ex_doc, "~> 0.38", only: [:dev, :test, :release], optional: true, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Kip Cole"],
      licenses: ["Apache-2.0"],
      links: links(),
      files: [
        "lib",
        "mix.exs",
        "README*",
        "CHANGELOG*",
        "LICENSE*"
      ]
    ]
  end

  defp links do
    %{
      "GitHub" => "https://github.com/elixir-tempo/jscalendar",
      "Readme" => "https://github.com/elixir-tempo/jscalendar/blob/v#{@version}/README.md",
      "Changelog" => "https://github.com/elixir-tempo/jscalendar/blob/v#{@version}/CHANGELOG.md",
      "RFC 8984" => "https://www.rfc-editor.org/rfc/rfc8984.html"
    }
  end

  defp docs do
    [
      source_ref: "v#{@version}",
      main: "readme",
      extras: ["README.md", "CHANGELOG.md", "LICENSE.md"],
      formatters: ["html", "markdown"],
      skip_undefined_reference_warnings_on: ["changelog", "CHANGELOG.md"],
      groups_for_modules: [
        "Calendar objects": [JSCalendar.Event, JSCalendar.Task, JSCalendar.Group],
        "What and where": [
          JSCalendar.Location,
          JSCalendar.VirtualLocation,
          JSCalendar.Link,
          JSCalendar.Relation
        ],
        Who: [JSCalendar.Participant],
        When: [
          JSCalendar.RecurrenceRule,
          JSCalendar.NDay,
          JSCalendar.Alert,
          JSCalendar.OffsetTrigger,
          JSCalendar.AbsoluteTrigger,
          JSCalendar.Occurrence,
          JSCalendar.TimeZone,
          JSCalendar.TimeZoneRule
        ],
        Patching: [JSCalendar.Patch],
        Internals: [JSCalendar.Object, JSCalendar.Type]
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
