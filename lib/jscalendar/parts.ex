defmodule JSCalendar.Relation do
  @moduledoc """
  How one calendar object relates to another
  ([RFC 8984 §4.1.3](https://www.rfc-editor.org/rfc/rfc8984.html#section-4.1.3)).

  A `Relation` is the *value* of a `relatedTo` entry; the key is the
  `uid` it points at. `relation` is a set drawn from `first`, `next`,
  `child` and `parent` — and an empty set is meaningful, saying the
  objects are related in some way the sender did not name.

  """

  use JSCalendar.Object,
    type: "Relation",
    properties: [
      {"relation", :relation, :string_set, nil}
    ]

  @type t :: %__MODULE__{relation: MapSet.t() | nil, extra: map()}
end

defmodule JSCalendar.Link do
  @moduledoc """
  An external resource associated with an object
  ([RFC 8984 §1.4.11](https://www.rfc-editor.org/rfc/rfc8984.html#section-1.4.11)).

  """

  use JSCalendar.Object,
    type: "Link",
    properties: [
      {"href", :href, :string, nil},
      {"cid", :cid, :string, nil},
      {"contentType", :content_type, :string, nil},
      {"size", :size, :unsigned_int, nil},
      {"rel", :rel, :string, nil},
      {"display", :display, {:enum, ~w(badge graphic fullsize thumbnail)}, nil},
      {"title", :title, :string, nil}
    ]

  @type t :: %__MODULE__{
          href: String.t() | nil,
          cid: String.t() | nil,
          content_type: String.t() | nil,
          size: non_neg_integer() | nil,
          rel: String.t() | nil,
          display: String.t() | nil,
          title: String.t() | nil,
          extra: map()
        }
end

defmodule JSCalendar.Location do
  @moduledoc """
  A physical location
  ([RFC 8984 §4.2.5](https://www.rfc-editor.org/rfc/rfc8984.html#section-4.2.5)).

  `relative_to` says which end of the object the location belongs to,
  which is how an itinerary distinguishes where something starts from
  where it finishes.

  """

  use JSCalendar.Object,
    type: "Location",
    properties: [
      {"name", :name, :string, nil},
      {"description", :description, :string, nil},
      {"locationTypes", :location_types, :string_set, nil},
      {"relativeTo", :relative_to, {:enum, ~w(start end)}, nil},
      {"timeZone", :time_zone, :string, nil},
      {"coordinates", :coordinates, :string, nil},
      {"links", :links, {:map_of, JSCalendar.Link}, nil}
    ]

  @type t :: %__MODULE__{
          name: String.t() | nil,
          description: String.t() | nil,
          location_types: MapSet.t() | nil,
          relative_to: String.t() | nil,
          time_zone: String.t() | nil,
          coordinates: String.t() | nil,
          links: %{optional(String.t()) => JSCalendar.Link.t()} | nil,
          extra: map()
        }
end

defmodule JSCalendar.VirtualLocation do
  @moduledoc """
  A virtual location — a conference bridge, a chat room
  ([RFC 8984 §4.2.6](https://www.rfc-editor.org/rfc/rfc8984.html#section-4.2.6)).

  """

  use JSCalendar.Object,
    type: "VirtualLocation",
    properties: [
      {"name", :name, :string, nil},
      {"description", :description, :string, nil},
      {"uri", :uri, :string, nil},
      {"features", :features, :string_set, nil}
    ]

  @type t :: %__MODULE__{
          name: String.t() | nil,
          description: String.t() | nil,
          uri: String.t() | nil,
          features: MapSet.t() | nil,
          extra: map()
        }
end

defmodule JSCalendar.NDay do
  @moduledoc """
  A weekday within a recurrence, optionally counted from the start or
  end of the period
  ([RFC 8984 §4.3.3](https://www.rfc-editor.org/rfc/rfc8984.html#section-4.3.3)).

  `nth_of_period: -1` with `day: "mo"` is "the last Monday".

  """

  use JSCalendar.Object,
    type: "NDay",
    properties: [
      {"day", :day, {:enum, ~w(mo tu we th fr sa su)}, nil},
      {"nthOfPeriod", :nth_of_period, :int, nil}
    ]

  @type t :: %__MODULE__{day: String.t() | nil, nth_of_period: integer() | nil, extra: map()}
end

defmodule JSCalendar.RecurrenceRule do
  @moduledoc """
  A repeat pattern
  ([RFC 8984 §4.3.3](https://www.rfc-editor.org/rfc/rfc8984.html#section-4.3.3)).

  This is JSCalendar's rendering of an iCalendar `RRULE`, with the
  parts named rather than packed into a string. `by_month` is a string
  rather than a number because a leap month in a lunisolar calendar is
  written `"3L"`.

  """

  use JSCalendar.Object,
    type: "RecurrenceRule",
    properties: [
      {"frequency", :frequency, {:enum, ~w(yearly monthly weekly daily hourly minutely secondly)},
       nil},
      {"interval", :interval, :unsigned_int, 1},
      {"rscale", :rscale, :string, "gregorian"},
      {"skip", :skip, {:enum, ~w(omit backward forward)}, "omit"},
      {"firstDayOfWeek", :first_day_of_week, {:enum, ~w(mo tu we th fr sa su)}, "mo"},
      {"byDay", :by_day, {:list_of, JSCalendar.NDay}, nil},
      {"byMonthDay", :by_month_day, {:list, :int}, nil},
      {"byMonth", :by_month, {:list, :string}, nil},
      {"byYearDay", :by_year_day, {:list, :int}, nil},
      {"byWeekNo", :by_week_no, {:list, :int}, nil},
      {"byHour", :by_hour, {:list, :unsigned_int}, nil},
      {"byMinute", :by_minute, {:list, :unsigned_int}, nil},
      {"bySecond", :by_second, {:list, :unsigned_int}, nil},
      {"bySetPosition", :by_set_position, {:list, :int}, nil},
      {"count", :count, :unsigned_int, nil},
      {"until", :until, :local_date_time, nil}
    ]

  @type t :: %__MODULE__{
          frequency: String.t() | nil,
          interval: pos_integer(),
          rscale: String.t(),
          skip: String.t(),
          first_day_of_week: String.t(),
          by_day: [JSCalendar.NDay.t()] | nil,
          by_month_day: [integer()] | nil,
          by_month: [String.t()] | nil,
          by_year_day: [integer()] | nil,
          by_week_no: [integer()] | nil,
          by_hour: [non_neg_integer()] | nil,
          by_minute: [non_neg_integer()] | nil,
          by_second: [non_neg_integer()] | nil,
          by_set_position: [integer()] | nil,
          count: non_neg_integer() | nil,
          until: NaiveDateTime.t() | nil,
          extra: map()
        }
end

defmodule JSCalendar.Participant do
  @moduledoc """
  Someone or something involved in the object
  ([RFC 8984 §4.4.6](https://www.rfc-editor.org/rfc/rfc8984.html#section-4.4.6)).

  A participant is not only a person: `kind` may be `location` or
  `resource`, which is how a room or a projector joins a meeting.
  `roles` is mandatory and is a set, because one participant is
  routinely both `attendee` and `chair`.

  The three `progress` properties apply only when the participant is
  taking part in a `JSCalendar.Task`.

  """

  use JSCalendar.Object,
    type: "Participant",
    properties: [
      {"name", :name, :string, nil},
      {"email", :email, :string, nil},
      {"description", :description, :string, nil},
      {"sendTo", :send_to, :string_map, nil},
      {"kind", :kind, {:enum, ~w(individual group location resource)}, nil},
      {"roles", :roles, :string_set, nil},
      {"locationId", :location_id, :string, nil},
      {"language", :language, :string, nil},
      {"participationStatus", :participation_status,
       {:enum, ~w(needs-action accepted declined tentative delegated)}, "needs-action"},
      {"participationComment", :participation_comment, :string, nil},
      {"expectReply", :expect_reply, :boolean, false},
      {"scheduleAgent", :schedule_agent, {:enum, ~w(server client none)}, "server"},
      {"scheduleForceSend", :schedule_force_send, :boolean, false},
      {"scheduleSequence", :schedule_sequence, :unsigned_int, 0},
      {"scheduleStatus", :schedule_status, {:list, :string}, nil},
      {"scheduleUpdated", :schedule_updated, :utc_date_time, nil},
      {"sentBy", :sent_by, :string, nil},
      {"invitedBy", :invited_by, :string, nil},
      {"delegatedTo", :delegated_to, :string_set, nil},
      {"delegatedFrom", :delegated_from, :string_set, nil},
      {"memberOf", :member_of, :string_set, nil},
      {"links", :links, {:map_of, JSCalendar.Link}, nil},
      {"progress", :progress, {:enum, ~w(needs-action in-process completed failed)}, nil},
      {"progressUpdated", :progress_updated, :utc_date_time, nil},
      {"percentComplete", :percent_complete, :unsigned_int, nil}
    ]

  @type t :: %__MODULE__{
          name: String.t() | nil,
          email: String.t() | nil,
          roles: MapSet.t() | nil,
          kind: String.t() | nil,
          participation_status: String.t(),
          expect_reply: boolean(),
          extra: map()
        }
end

defmodule JSCalendar.OffsetTrigger do
  @moduledoc """
  An alert fired relative to the object's start or end
  ([RFC 8984 §4.5.2](https://www.rfc-editor.org/rfc/rfc8984.html#section-4.5.2)).

  The offset is a *signed* duration: `-PT15M` is the usual "fifteen
  minutes beforehand".

  """

  use JSCalendar.Object,
    type: "OffsetTrigger",
    properties: [
      {"offset", :offset, :duration, nil},
      {"relativeTo", :relative_to, {:enum, ~w(start end)}, "start"}
    ]

  @type t :: %__MODULE__{offset: Duration.t() | nil, relative_to: String.t(), extra: map()}
end

defmodule JSCalendar.AbsoluteTrigger do
  @moduledoc """
  An alert fired at a fixed moment
  ([RFC 8984 §4.5.1](https://www.rfc-editor.org/rfc/rfc8984.html#section-4.5.1)).

  """

  use JSCalendar.Object,
    type: "AbsoluteTrigger",
    properties: [
      {"when", :when, :utc_date_time, nil}
    ]

  @type t :: %__MODULE__{when: DateTime.t() | nil, extra: map()}
end

defmodule JSCalendar.Alert do
  @moduledoc """
  A reminder attached to an object
  ([RFC 8984 §4.5.2](https://www.rfc-editor.org/rfc/rfc8984.html#section-4.5.2)).

  The trigger is one of `JSCalendar.OffsetTrigger`,
  `JSCalendar.AbsoluteTrigger`, or — for a kind this library does not
  know — the raw map. RFC 8984 requires an unrecognised trigger to be
  preserved rather than dropped, since the alert still belongs to the
  object even if this implementation cannot fire it.

  """

  alias JSCalendar.AbsoluteTrigger
  alias JSCalendar.OffsetTrigger

  use JSCalendar.Object,
    type: "Alert",
    properties: [
      {"trigger", :trigger, :any, nil},
      {"acknowledged", :acknowledged, :utc_date_time, nil},
      {"relatedTo", :related_to, {:map_of, JSCalendar.Relation}, nil},
      {"action", :action, {:enum, ~w(display email)}, "display"}
    ]

  @type t :: %__MODULE__{
          trigger: JSCalendar.OffsetTrigger.t() | JSCalendar.AbsoluteTrigger.t() | map() | nil,
          acknowledged: DateTime.t() | nil,
          action: String.t(),
          extra: map()
        }

  def from_map(map) do
    with {:ok, alert} <- super(map) do
      {:ok, %{alert | trigger: decode_trigger(alert.trigger)}}
    end
  end

  def to_map(%__MODULE__{} = alert) do
    case super(alert) do
      %{"trigger" => trigger} = encoded -> Map.put(encoded, "trigger", encode_trigger(trigger))
      encoded -> encoded
    end
  end

  # RFC 8984 §4.5.2 names two trigger kinds and reserves room for
  # more. One this library does not know still belongs to the alert,
  # so it is kept as its raw map rather than refused.
  defp decode_trigger(%{"@type" => "OffsetTrigger"} = map) do
    case OffsetTrigger.from_map(map) do
      {:ok, trigger} -> trigger
      {:error, _reason} -> map
    end
  end

  defp decode_trigger(%{"@type" => "AbsoluteTrigger"} = map) do
    case AbsoluteTrigger.from_map(map) do
      {:ok, trigger} -> trigger
      {:error, _reason} -> map
    end
  end

  defp decode_trigger(other), do: other

  defp encode_trigger(%OffsetTrigger{} = trigger),
    do: OffsetTrigger.to_map(trigger)

  defp encode_trigger(%AbsoluteTrigger{} = trigger),
    do: AbsoluteTrigger.to_map(trigger)

  defp encode_trigger(other), do: other
end
