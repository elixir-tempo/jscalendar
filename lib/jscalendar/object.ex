defmodule JSCalendar.Object do
  @moduledoc """
  Declares a JSCalendar object from its property table.

  Every object in RFC 8984 is the same shape — a JSON object with an
  `@type` discriminator and a fixed set of typed properties — so each
  one here is a property table rather than a hand-written parser:

      use JSCalendar.Object,
        type: "Link",
        properties: [
          {"href", :href, :string, nil},
          {"contentType", :content_type, :string, nil}
        ]

  Each entry is `{json_name, struct_key, type, default}`. The macro
  generates the struct, `from_map/1` and `to_map/1`.

  ### Two properties of the generated code worth knowing

  **Unknown properties survive.** Anything the table does not name is
  kept in `extra` and written back untouched. RFC 8984 §1.5 requires
  this: vendor extensions and later revisions of the spec both arrive
  as properties an implementation has never heard of, and a parser
  that drops them silently corrupts data it was only asked to read.

  **Defaults are not written back.** A property equal to its RFC
  default is omitted on encode, because the default is what its
  absence already means. This keeps output small and makes a round
  trip idempotent rather than steadily more verbose.

  """

  alias JSCalendar.Type

  @doc false
  defmacro __using__(options) do
    type = Keyword.fetch!(options, :type)

    # The property table arrives as AST, so it is evaluated here rather
    # than pattern-matched: `{"href", :href, :string, nil}` is a
    # three-element `{:{}, meta, args}` node until it is.
    {declared, _binding} = Code.eval_quoted(Keyword.fetch!(options, :properties), [], __CALLER__)

    properties =
      if Keyword.get(options, :common, false), do: common() ++ declared, else: declared

    struct_fields = Enum.map(properties, fn {_json, key, _spec, default} -> {key, default} end)

    quote do
      alias JSCalendar.Type

      @jscalendar_type unquote(type)
      @properties unquote(Macro.escape(properties))

      defstruct unquote(Macro.escape(struct_fields)) ++ [extra: %{}]

      @doc """
      The `@type` value RFC 8984 gives this object.

      ### Returns

      * the type name as a string.

      """
      @spec jscalendar_type() :: String.t()
      def jscalendar_type, do: @jscalendar_type

      @doc """
      Read this object from a decoded JSON map.

      ### Arguments

      * `map` is a map with string keys, as `JSON.decode/1` returns.

      ### Returns

      * `{:ok, object}`; or

      * `{:error, reason}` when a property does not match its declared
        type.

      """
      @spec from_map(map()) :: {:ok, struct()} | {:error, term()}
      def from_map(map) when is_map(map) do
        unquote(__MODULE__).build(__MODULE__, %__MODULE__{}, @properties, map)
      end

      def from_map(other), do: {:error, {:not_an_object, other}}

      @doc """
      Write this object back to a JSON-ready map.

      ### Arguments

      * `object` is a `t:t/0`.

      ### Returns

      * a map with string keys, ready for `JSON.encode/1`.

      """
      @spec to_map(struct()) :: map()
      def to_map(%__MODULE__{} = object) do
        unquote(__MODULE__).dump(@jscalendar_type, @properties, object)
      end

      # A handful of properties are polymorphic — a group's mixed
      # entries, an alert's trigger — and cannot be described by a
      # single type in the table. Those objects override these to
      # finish the job.
      defoverridable from_map: 1, to_map: 1
    end
  end

  # The properties RFC 8984 §4 gives to every calendar object. Shared
  # rather than repeated three times, so Event, Task and Group cannot
  # drift apart on the half of the specification they hold in common.
  defp common do
    [
      {"uid", :uid, :string, nil},
      {"relatedTo", :related_to, {:map_of, JSCalendar.Relation}, nil},
      {"prodId", :prod_id, :string, nil},
      {"created", :created, :utc_date_time, nil},
      {"updated", :updated, :utc_date_time, nil},
      {"sequence", :sequence, :unsigned_int, 0},
      {"method", :method, :string, nil},
      {"title", :title, :string, ""},
      {"description", :description, :string, ""},
      {"descriptionContentType", :description_content_type, :string, "text/plain"},
      {"showWithoutTime", :show_without_time, :boolean, false},
      {"locations", :locations, {:map_of, JSCalendar.Location}, nil},
      {"virtualLocations", :virtual_locations, {:map_of, JSCalendar.VirtualLocation}, nil},
      {"links", :links, {:map_of, JSCalendar.Link}, nil},
      {"locale", :locale, :string, nil},
      {"keywords", :keywords, :string_set, nil},
      {"categories", :categories, :string_set, nil},
      {"color", :color, :string, nil},
      {"recurrenceId", :recurrence_id, :local_date_time, nil},
      {"recurrenceIdTimeZone", :recurrence_id_time_zone, :string, nil},
      {"recurrenceRules", :recurrence_rules, {:list_of, JSCalendar.RecurrenceRule}, nil},
      {"excludedRecurrenceRules", :excluded_recurrence_rules,
       {:list_of, JSCalendar.RecurrenceRule}, nil},
      {"recurrenceOverrides", :recurrence_overrides, {:patch_map, :local_date_time}, nil},
      {"excluded", :excluded, :boolean, false},
      {"priority", :priority, :int, 0},
      {"freeBusyStatus", :free_busy_status, {:enum, ~w(free busy)}, "busy"},
      {"privacy", :privacy, {:enum, ~w(public private secret)}, "public"},
      {"replyTo", :reply_to, :string_map, nil},
      {"sentBy", :sent_by, :string, nil},
      {"participants", :participants, {:map_of, JSCalendar.Participant}, nil},
      {"requestStatus", :request_status, :string, nil},
      {"useDefaultAlerts", :use_default_alerts, :boolean, false},
      {"alerts", :alerts, {:map_of, JSCalendar.Alert}, nil},
      {"localizations", :localizations, {:patch_map, :string}, nil},
      {"timeZone", :time_zone, :string, nil},
      {"timeZones", :time_zones, {:map_of, JSCalendar.TimeZone}, nil}
    ]
  end

  @doc false
  @spec build(module(), struct(), list(), map()) :: {:ok, struct()} | {:error, term()}
  def build(module, empty, properties, map) do
    named = MapSet.new(properties, fn {json, _key, _spec, _default} -> json end)

    properties
    |> Enum.reduce_while({:ok, empty}, fn {json, key, spec, _default}, {:ok, acc} ->
      case Type.decode(Map.get(map, json), spec) do
        {:ok, nil} -> {:cont, {:ok, acc}}
        {:ok, value} -> {:cont, {:ok, Map.put(acc, key, value)}}
        {:error, reason} -> {:halt, {:error, {module, json, reason}}}
      end
    end)
    |> case do
      {:ok, object} -> {:ok, %{object | extra: unnamed(map, named)}}
      {:error, _reason} = error -> error
    end
  end

  # `@type` is consumed by the dispatcher rather than stored, so it is
  # not "unknown" — writing it into `extra` would emit it twice.
  defp unnamed(map, named) do
    Map.reject(map, fn {json, _value} -> json == "@type" or MapSet.member?(named, json) end)
  end

  @doc false
  @spec dump(String.t(), list(), struct()) :: map()
  def dump(type, properties, object) do
    properties
    |> Enum.reduce(%{"@type" => type}, fn {json, key, spec, default}, acc ->
      case Map.fetch!(object, key) do
        ^default -> acc
        value -> Map.put(acc, json, Type.encode(value, spec))
      end
    end)
    |> Map.merge(object.extra)
  end
end
