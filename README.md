# JSCalendar

[RFC 8984](https://www.rfc-editor.org/rfc/rfc8984.html) for Elixir — the JSON representation of calendar data.

JSCalendar says what iCalendar says — events, tasks, recurrence, participants, time zones — in a form that does not need its own parser. It is the IETF's intended successor to iCalendar, and where iCalendar's line folding, backslash escaping and property parameters have produced two decades of interoperability bugs, this is a JSON object with named fields.

```elixir
{:ok, event} = JSCalendar.decode(~s({
  "@type": "Event",
  "uid": "a8df6573-0474-496d-8496-033ad45d7fea",
  "updated": "2020-01-02T18:23:04Z",
  "title": "Some event",
  "start": "2020-01-15T13:00:00",
  "timeZone": "America/New_York",
  "duration": "PT1H"
}))

event.start     #=> ~N[2020-01-15 13:00:00]
event.duration  #=> %Duration{hour: 1}

JSCalendar.Event.ends_at(event)
#=> ~N[2020-01-15 14:00:00]
```

This library reads and writes the format. It does not schedule, and it does not expand recurrences.

## No dependencies

Erlang's `:json` and Elixir's `Duration` are both standard library, so nothing is pulled in to parse a document or read a duration. Values map to standard types rather than to types invented here:

| JSCalendar | Elixir |
| --- | --- |
| `LocalDateTime` | `NaiveDateTime` |
| `UTCDateTime` | `DateTime` in `Etc/UTC` |
| `Duration`, `SignedDuration` | `Duration` |
| `String[Boolean]` | `MapSet` |
| `Id[Foo]` | `%{String.t() => Foo.t()}` |

A `String[Boolean]` is a set written as an object whose values are all `true`, so it reads back as a `MapSet` — `"elixir" in event.keywords` rather than a map lookup against a value carrying no information.

## Start and duration, not start and end

An event has a `start` and a `duration`. That is not a stylistic choice. The end of an event is `start + duration` **in the event's own time zone**, so an hour-long meeting stays an hour long across a daylight-saving boundary, where a stored end time would silently become two hours or none.

`start` is a `LocalDateTime` — wall clock, no offset — and `timeZone` names the zone it is read in. A `nil` time zone is a floating event: the same wall-clock time wherever the reader is, which is what "New Year's Eve, midnight" actually means.

## Unknown properties survive

Vendor extensions and later revisions of the specification both arrive as properties this library has never heard of. They are kept in each object's `extra` map and written back untouched:

```elixir
{:ok, event} = JSCalendar.decode(~s({"@type":"Event","uid":"e","example.com:mood":"cheerful"}))
event.extra
#=> %{"example.com:mood" => "cheerful"}
```

A reader that silently drops what it does not understand corrupts data it was only asked to relay. The same holds inside a group: RFC 8984 requires entries of an unrecognised type to be **ignored**, not rejected and not deleted, so they survive a read-modify-write cycle as their raw maps.

## Defaults are not written back

A property equal to its RFC default is omitted on encode — its absence already says the same thing:

```elixir
{:ok, event} = JSCalendar.decode(~s({"@type":"Event","uid":"e"}))
event.privacy                       #=> "public"   (the default, applied on read)
JSCalendar.to_map(event)            #=> %{"@type" => "Event", "uid" => "e"}
```

So a document does not grow every time it is read and rewritten, and encoding is idempotent.

## What is not here yet

`recurrenceOverrides`, `localizations` and custom `timeZones` are preserved verbatim rather than parsed into structures. They are PatchObjects and time zone definitions whose semantics deserve their own attention rather than a hurried first pass — they round-trip correctly, they are simply not yet typed.

## Installation

```elixir
def deps do
  [
    {:jscalendar, "~> 0.1"}
  ]
end
```

Requires Elixir 1.17 and OTP 27 or later — OTP 27 is where Erlang's `:json` arrived.

## License

Apache-2.0. See [LICENSE.md](LICENSE.md).
