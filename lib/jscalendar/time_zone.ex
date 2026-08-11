defmodule JSCalendar.TimeZoneRule do
  @moduledoc """
  One offset a custom time zone observes, and when it starts
  ([RFC 8984 §4.7.2](https://www.rfc-editor.org/rfc/rfc8984.html#section-4.7.2)).

  A rule is the JSCalendar equivalent of an iCalendar `STANDARD` or
  `DAYLIGHT` subcomponent: from `start`, the zone stops using
  `offset_from` and begins using `offset_to`, and `recurrence_rules`
  says when that happens again.

  `start` is a local time in `offset_from` — the offset being left, not
  the one being joined — because the transition is announced in the
  clock reading that people still have at that moment.

  """

  use JSCalendar.Object,
    type: "TimeZoneRule",
    properties: [
      {"start", :start, :local_date_time, nil},
      {"offsetFrom", :offset_from, :string, nil},
      {"offsetTo", :offset_to, :string, nil},
      {"recurrenceRules", :recurrence_rules, {:list_of, JSCalendar.RecurrenceRule}, nil},
      # RFC 8984 requires every patch here to be the empty object: the
      # only thing a rule's overrides can say is "and also on this date",
      # since there is nothing about a transition to vary.
      {"recurrenceOverrides", :recurrence_overrides, {:patch_map, :local_date_time}, nil},
      {"names", :names, :string_set, nil},
      {"comments", :comments, {:list, :string}, nil}
    ]

  @type t :: %__MODULE__{
          start: NaiveDateTime.t() | nil,
          offset_from: String.t() | nil,
          offset_to: String.t() | nil,
          recurrence_rules: [JSCalendar.RecurrenceRule.t()] | nil,
          recurrence_overrides: %{optional(NaiveDateTime.t()) => JSCalendar.Patch.t()} | nil,
          names: MapSet.t() | nil,
          comments: [String.t()] | nil,
          extra: map()
        }
end

defmodule JSCalendar.TimeZone do
  @moduledoc """
  A time zone defined in the file rather than named from a database
  ([RFC 8984 §4.7.2](https://www.rfc-editor.org/rfc/rfc8984.html#section-4.7.2)).

  Most objects name their zone — `"timeZone": "Australia/Sydney"` — and
  leave the offsets to the IANA database. A custom zone exists for the
  cases where that is not enough: a sender whose database is newer than
  the recipient's, or a zone that is not in any database at all.

  `standard` and `daylight` are lists of `t:JSCalendar.TimeZoneRule.t/0`,
  and `valid_until` is the sender's honesty about how far ahead the
  rules can be trusted.

  A custom zone's `tz_id` **must** start with `/`, which is what keeps
  it from being mistaken for an IANA name.

  """

  use JSCalendar.Object,
    type: "TimeZone",
    properties: [
      {"tzId", :tz_id, :string, nil},
      {"updated", :updated, :utc_date_time, nil},
      {"url", :url, :string, nil},
      {"validUntil", :valid_until, :utc_date_time, nil},
      {"aliases", :aliases, :string_set, nil},
      {"standard", :standard, {:list_of, JSCalendar.TimeZoneRule}, nil},
      {"daylight", :daylight, {:list_of, JSCalendar.TimeZoneRule}, nil}
    ]

  @type t :: %__MODULE__{
          tz_id: String.t() | nil,
          updated: DateTime.t() | nil,
          url: String.t() | nil,
          valid_until: DateTime.t() | nil,
          aliases: MapSet.t() | nil,
          standard: [JSCalendar.TimeZoneRule.t()] | nil,
          daylight: [JSCalendar.TimeZoneRule.t()] | nil,
          extra: map()
        }
end
