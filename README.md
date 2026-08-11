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

This library reads and writes the format. It does not schedule, and it does not expand recurrence rules — though it does build the individual occurrences a rule produces, once someone else has said when they fall.

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

## Patches, and the objects built from them

Three of RFC 8984's properties are tables of **PatchObjects** — `recurrenceOverrides`, `localizations`, and the empty patches a time zone rule uses. A patch is how JSCalendar says "the same as that, but different here": each key is a path, each value is what to put there, and `null` removes.

```elixir
JSCalendar.Patch.apply(%{"title" => "Standup"}, %{"title" => "Retro"})
#=> {:ok, %{"title" => "Retro"}}
```

`JSCalendar.Patch` is a module rather than a map lookup because four rules decide whether a patch may be applied *at all*, and the specification is emphatic about what happens when one fails: reject it **in its entirety**, never partially. A pointer may not reach inside an array, every part before the last must already exist, and no pointer may be a prefix of another — `alerts` and `alerts/1/offset` in one patch have no defined order, so the result would depend on which went first.

```elixir
JSCalendar.Patch.validate(%{"alerts" => %{}, "alerts/1/offset" => "-PT5M"})
#=> {:error, {:overlapping_pointers, "alerts", "alerts/1/offset"}}
```

`JSCalendar.Occurrence` is what that buys. Give it a recurrence id and it returns the object for that instance — the base, shifted to that moment, with the override applied, the recurrence machinery stripped, and the pointers RFC 8984 says to *ignore* skipped rather than refused:

```elixir
JSCalendar.Occurrence.at(lecture, ~N[2020-06-25 09:00:00])
#=> {:ok, %JSCalendar.Event{title: "Calculus I Exam", start: ~N[2020-06-25 10:00:00], ...}}

JSCalendar.Occurrence.at(lecture, ~N[2020-04-01 09:00:00])
#=> :excluded
```

Exclusion is a separate answer, not an empty one. A caller expanding a rule has to tell "this occurrence was cancelled" apart from "this occurrence could not be built", and a tuple that could mean either would make that impossible.

## Time zones defined in the file

Most objects name their zone and leave the offsets to the IANA database. `JSCalendar.TimeZone` covers the cases where that is not enough — a sender whose database is newer than the recipient's, or a zone in no database at all — as `standard` and `daylight` lists of `JSCalendar.TimeZoneRule`, each saying which offset is being left, which joined, and when it happens again.

## What is not here yet

Expanding a recurrence *rule* into the set of dates it generates. That is calendar arithmetic rather than a format concern, and [`ex_tempo`](https://hex.pm/packages/ex_tempo) already does it — `Tempo.JSCalendar` puts the two together and hands back intervals.

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
