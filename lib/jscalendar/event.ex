defmodule JSCalendar.Event do
  @moduledoc """
  Something that happens at a particular time
  ([RFC 8984 §5.1](https://www.rfc-editor.org/rfc/rfc8984.html#section-5.1)).

  An event has a `start` and a `duration` rather than a start and an
  end. That is not a stylistic choice: the end of an event is
  `start + duration` *in the event's own time zone*, so an hour-long
  meeting stays an hour long across a daylight-saving boundary, where
  a stored end time would silently become two hours or none.

  `start` is a `LocalDateTime` — wall-clock, with no offset — and
  `time_zone` names the zone it is read in. A `nil` time zone means a
  floating event: the same wall-clock time wherever the reader is,
  which is what "New Year's Eve, midnight" actually means.

  ### Example

      iex> {:ok, event} = JSCalendar.Event.from_map(%{
      ...>   "@type" => "Event",
      ...>   "uid" => "review-2026-06",
      ...>   "updated" => "2026-06-01T09:00:00Z",
      ...>   "title" => "Quarterly review",
      ...>   "start" => "2026-06-02T09:00:00",
      ...>   "timeZone" => "Australia/Sydney",
      ...>   "duration" => "PT1H"
      ...> })
      iex> {event.title, event.start, event.duration}
      {"Quarterly review", ~N[2026-06-02 09:00:00], %Duration{hour: 1}}

  """

  use JSCalendar.Object,
    type: "Event",
    common: true,
    properties: [
      {"start", :start, :local_date_time, nil},
      {"duration", :duration, :duration, nil},
      {"status", :status, {:enum, ~w(tentative confirmed cancelled)}, nil}
    ]

  @typedoc "A calendar event."
  @type t :: %__MODULE__{
          uid: String.t() | nil,
          title: String.t(),
          description: String.t(),
          start: NaiveDateTime.t() | nil,
          duration: Duration.t() | nil,
          time_zone: String.t() | nil,
          status: String.t() | nil,
          participants: %{optional(String.t()) => JSCalendar.Participant.t()} | nil,
          locations: %{optional(String.t()) => JSCalendar.Location.t()} | nil,
          recurrence_rules: [JSCalendar.RecurrenceRule.t()] | nil,
          extra: map()
        }

  @doc """
  The event's duration, defaulting as RFC 8984 requires.

  `duration` is optional and defaults to `PT0S` when absent, so an
  event with no duration is an instant rather than one of unknown
  length. Reading the field directly gives `nil`; this gives the
  meaning.

  ### Arguments

  * `event` is a `t:t/0`.

  ### Returns

  * a `t:Duration.t/0`.

  ### Examples

      iex> JSCalendar.Event.duration(%JSCalendar.Event{duration: %Duration{hour: 1}})
      %Duration{hour: 1}

      iex> JSCalendar.Event.duration(%JSCalendar.Event{})
      %Duration{}

  """
  @spec duration(t()) :: Duration.t()
  def duration(%__MODULE__{duration: nil}), do: %Duration{}
  def duration(%__MODULE__{duration: duration}), do: duration

  @doc """
  When the event ends, in its own time zone.

  ### Arguments

  * `event` is a `t:t/0`.

  ### Returns

  * a `t:NaiveDateTime.t/0`, or `nil` when the event has no `start`.

  ### Examples

      iex> event = %JSCalendar.Event{start: ~N[2026-06-02 09:00:00], duration: %Duration{hour: 1}}
      iex> JSCalendar.Event.ends_at(event)
      ~N[2026-06-02 10:00:00]

  """
  @spec ends_at(t()) :: NaiveDateTime.t() | nil
  def ends_at(%__MODULE__{start: nil}), do: nil

  def ends_at(%__MODULE__{start: start} = event) do
    NaiveDateTime.shift(start, duration(event))
  end
end

defmodule JSCalendar.Task do
  @moduledoc """
  Something to be done, optionally by a certain time
  ([RFC 8984 §5.2](https://www.rfc-editor.org/rfc/rfc8984.html#section-5.2)).

  A task differs from an event in what it may leave out. Both `start`
  and `due` are optional, because "someday" is a real state for a task
  and not for a meeting, and `estimated_duration` is how long the work
  takes rather than how long it occupies the calendar.

  """

  use JSCalendar.Object,
    type: "Task",
    common: true,
    properties: [
      {"due", :due, :local_date_time, nil},
      {"start", :start, :local_date_time, nil},
      {"estimatedDuration", :estimated_duration, :duration, nil},
      {"percentComplete", :percent_complete, :unsigned_int, nil},
      {"progress", :progress, {:enum, ~w(needs-action in-process completed failed)}, nil},
      {"progressUpdated", :progress_updated, :utc_date_time, nil},
      {"status", :status, {:enum, ~w(needs-action in-process completed cancelled pending failed)},
       nil}
    ]

  @typedoc "A calendar task."
  @type t :: %__MODULE__{
          uid: String.t() | nil,
          title: String.t(),
          due: NaiveDateTime.t() | nil,
          start: NaiveDateTime.t() | nil,
          estimated_duration: Duration.t() | nil,
          percent_complete: non_neg_integer() | nil,
          progress: String.t() | nil,
          status: String.t() | nil,
          extra: map()
        }
end

defmodule JSCalendar.Group do
  @moduledoc """
  A collection of events and tasks
  ([RFC 8984 §5.3](https://www.rfc-editor.org/rfc/rfc8984.html#section-5.3)).

  `entries` is mandatory and mixed — events and tasks together — and
  RFC 8984 requires that entries of a type the reader does not
  recognise are **ignored** rather than treated as an error. Those are
  kept in `unknown_entries` instead of discarded, so a group can be
  read, changed and written back without quietly losing the members
  this implementation did not understand.

  """

  alias JSCalendar.Event
  alias JSCalendar.Task

  use JSCalendar.Object,
    type: "Group",
    common: true,
    properties: [
      {"entries", :entries, :any, nil},
      {"source", :source, {:object, JSCalendar.Link}, nil}
    ]

  @typedoc "A group of calendar objects."
  @type t :: %__MODULE__{
          uid: String.t() | nil,
          title: String.t(),
          entries: [JSCalendar.Event.t() | JSCalendar.Task.t()] | nil,
          source: JSCalendar.Link.t() | nil,
          extra: map()
        }

  def from_map(map) do
    with {:ok, group} <- super(map) do
      {:ok, %{group | entries: Enum.map(List.wrap(group.entries), &decode_entry/1)}}
    end
  end

  def to_map(%__MODULE__{} = group) do
    group
    |> super()
    |> then(fn map ->
      case group.entries do
        nil -> map
        entries -> Map.put(map, "entries", Enum.map(entries, &encode_entry/1))
      end
    end)
  end

  # "Implementations MUST ignore entries of unknown type" — ignore, not
  # reject and not drop. An unreadable member is kept as its raw map so
  # that reading a group and writing it back does not delete the parts
  # this library is too old to understand.
  defp decode_entry(%{"@type" => "Event"} = entry) do
    case Event.from_map(entry) do
      {:ok, event} -> event
      {:error, _reason} -> entry
    end
  end

  defp decode_entry(%{"@type" => "Task"} = entry) do
    case Task.from_map(entry) do
      {:ok, task} -> task
      {:error, _reason} -> entry
    end
  end

  defp decode_entry(entry), do: entry

  defp encode_entry(%Event{} = entry), do: Event.to_map(entry)
  defp encode_entry(%Task{} = entry), do: Task.to_map(entry)
  defp encode_entry(entry), do: entry
end
