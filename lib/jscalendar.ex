defmodule JSCalendar do
  @moduledoc """
  JSCalendar — the JSON representation of calendar data
  ([RFC 8984](https://www.rfc-editor.org/rfc/rfc8984.html)).

  JSCalendar says what iCalendar says — events, tasks, recurrence,
  participants, time zones — in a form that does not need its own
  parser. It is the IETF's intended successor to iCalendar, and where
  iCalendar's line-folding, escaping and property parameters have
  produced two decades of interoperability bugs, this is a JSON object
  with named fields.

  This library reads and writes that format. It does not schedule, and
  it does not expand recurrences; it turns documents into structs and
  back, faithfully.

      iex> {:ok, event} = JSCalendar.decode(~s({
      ...>   "@type": "Event",
      ...>   "uid": "review-2026-06",
      ...>   "updated": "2026-06-01T09:00:00Z",
      ...>   "title": "Quarterly review",
      ...>   "start": "2026-06-02T09:00:00",
      ...>   "duration": "PT1H"
      ...> }))
      iex> {event.title, event.start}
      {"Quarterly review", ~N[2026-06-02 09:00:00]}

  ### Three things it takes seriously

  **Unknown properties survive.** Vendor extensions and later
  revisions of the specification both arrive as properties this
  library has never heard of. They are kept in each object's `extra`
  map and written back untouched, because a reader that silently drops
  what it does not understand corrupts data it was only asked to
  relay.

  **Defaults are not written back.** A property equal to its RFC
  default is omitted on encode — its absence already says the same
  thing — so a document does not grow every time it is read and
  rewritten.

  **No dependencies.** Erlang's `:json` and Elixir's `Duration` are
  both standard library, so nothing is pulled in to parse a document
  or read a duration.

  ### What is not here yet

  `recurrenceOverrides`, `localizations` and custom `timeZones` are
  preserved verbatim rather than parsed into structures — they are
  PatchObjects and time zone definitions whose semantics deserve their
  own attention rather than a hurried first pass. They round-trip
  correctly; they are simply not yet typed.

  """

  alias JSCalendar.Event
  alias JSCalendar.Group
  alias JSCalendar.Task

  @typedoc "Any top-level JSCalendar object."
  @type t :: Event.t() | Task.t() | Group.t()

  @objects %{"Event" => Event, "Task" => Task, "Group" => Group}

  @doc """
  Read a JSCalendar document.

  The object type is taken from `@type`, which RFC 8984 makes
  mandatory on every object.

  ### Arguments

  * `json` is a JSCalendar document as a string.

  ### Returns

  * `{:ok, object}` — a `t:JSCalendar.Event.t/0`,
    `t:JSCalendar.Task.t/0` or `t:JSCalendar.Group.t/0`; or

  * `{:error, reason}` when the document is not valid JSON, carries no
    recognised `@type`, or holds a property that does not match its
    declared type.

  ### Examples

      iex> {:ok, task} = JSCalendar.decode(~s({"@type":"Task","uid":"t1","title":"Write it up"}))
      iex> task.title
      "Write it up"

      iex> JSCalendar.decode(~s({"@type":"Sandwich"}))
      {:error, {:unknown_type, "Sandwich"}}

      iex> JSCalendar.decode("not json")
      {:error, :invalid_json}

  """
  @spec decode(String.t()) :: {:ok, t()} | {:error, term()}
  def decode(json) when is_binary(json) do
    case parse(json) do
      {:ok, map} -> from_map(map)
      :error -> {:error, :invalid_json}
    end
  end

  # `:json.decode/1` raises on malformed input rather than answering
  # with a tuple, and a library must not crash its caller on a document
  # that merely turned out to be rubbish.
  defp parse(json) do
    {:ok, :json.decode(json)}
  rescue
    _error -> :error
  catch
    _kind, _value -> :error
  end

  @doc """
  Read a JSCalendar object from an already-decoded map.

  Use this when the document arrived as part of a larger payload — a
  JMAP response, say — and has been decoded once already.

  ### Arguments

  * `map` is a map with string keys.

  ### Returns

  * `{:ok, object}`; or

  * `{:error, reason}`.

  ### Examples

      iex> {:ok, event} = JSCalendar.from_map(%{"@type" => "Event", "uid" => "e1"})
      iex> event.uid
      "e1"

      iex> JSCalendar.from_map(%{"uid" => "e1"})
      {:error, :missing_type}

  """
  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(%{"@type" => type} = map) when is_binary(type) do
    case Map.fetch(@objects, type) do
      {:ok, module} -> module.from_map(map)
      :error -> {:error, {:unknown_type, type}}
    end
  end

  def from_map(map) when is_map(map), do: {:error, :missing_type}
  def from_map(other), do: {:error, {:not_an_object, other}}

  @doc """
  Write a JSCalendar object as a document.

  ### Arguments

  * `object` is a `t:JSCalendar.Event.t/0`,
    `t:JSCalendar.Task.t/0` or `t:JSCalendar.Group.t/0`.

  ### Returns

  * `{:ok, json}`.

  ### Examples

      iex> {:ok, json} = JSCalendar.encode(%JSCalendar.Event{uid: "e1"})
      iex> :json.decode(json)["@type"]
      "Event"

  """
  @spec encode(t()) :: {:ok, String.t()}
  def encode(object) do
    {:ok, object |> to_map() |> :json.encode() |> IO.iodata_to_binary()}
  end

  @doc """
  Write a JSCalendar object as a JSON-ready map.

  ### Arguments

  * `object` is a `t:JSCalendar.Event.t/0`,
    `t:JSCalendar.Task.t/0` or `t:JSCalendar.Group.t/0`.

  ### Returns

  * a map with string keys.

  ### Examples

      iex> JSCalendar.to_map(%JSCalendar.Event{uid: "e1"}) |> Map.get("uid")
      "e1"

  """
  @spec to_map(t()) :: map()
  def to_map(%Event{} = object), do: Event.to_map(object)
  def to_map(%Task{} = object), do: Task.to_map(object)
  def to_map(%Group{} = object), do: Group.to_map(object)
end
