defmodule JSCalendarTest do
  use ExUnit.Case, async: true

  alias JSCalendar.Event
  alias JSCalendar.Group
  alias JSCalendar.Link
  alias JSCalendar.Location
  alias JSCalendar.Occurrence
  alias JSCalendar.Participant
  alias JSCalendar.Patch
  alias JSCalendar.RecurrenceRule
  alias JSCalendar.Task
  alias JSCalendar.TimeZone
  alias JSCalendar.TimeZoneRule

  doctest JSCalendar
  doctest JSCalendar.Event
  doctest JSCalendar.Type
  doctest JSCalendar.Patch
  doctest JSCalendar.Occurrence

  # RFC 8984 §6.1 — a simple event.
  @simple_event ~s({
    "@type": "Event",
    "uid": "a8df6573-0474-496d-8496-033ad45d7fea",
    "updated": "2020-01-02T18:23:04Z",
    "title": "Some event",
    "start": "2020-01-15T13:00:00",
    "timeZone": "America/New_York",
    "duration": "PT1H"
  })

  describe "decoding" do
    test "a simple event, as RFC 8984 §6.1 gives it" do
      assert {:ok, %Event{} = event} = JSCalendar.decode(@simple_event)

      assert event.uid == "a8df6573-0474-496d-8496-033ad45d7fea"
      assert event.title == "Some event"
      assert event.start == ~N[2020-01-15 13:00:00]
      assert event.time_zone == "America/New_York"
      assert event.duration == %Duration{hour: 1}
      assert event.updated == ~U[2020-01-02 18:23:04Z]
    end

    test "the object type comes from @type" do
      assert {:ok, %Event{}} = JSCalendar.decode(~s({"@type":"Event","uid":"e"}))
      assert {:ok, %Task{}} = JSCalendar.decode(~s({"@type":"Task","uid":"t"}))
      assert {:ok, %Group{}} = JSCalendar.decode(~s({"@type":"Group","uid":"g"}))
    end

    test "a missing or unknown @type is an error, not a guess" do
      assert JSCalendar.from_map(%{"uid" => "e"}) == {:error, :missing_type}

      assert JSCalendar.from_map(%{"@type" => "Sandwich"}) ==
               {:error, {:unknown_type, "Sandwich"}}
    end

    test "invalid JSON is an error, not a crash" do
      assert JSCalendar.decode("{{{") == {:error, :invalid_json}
      assert JSCalendar.decode("") == {:error, :invalid_json}
    end

    test "a property of the wrong type is reported with its name" do
      assert {:error, {Event, "start", {:invalid_local_date_time, "yesterday"}}} =
               JSCalendar.decode(~s({"@type":"Event","start":"yesterday"}))
    end

    test "defaults are applied when a property is absent" do
      assert {:ok, event} = JSCalendar.decode(~s({"@type":"Event","uid":"e"}))

      assert event.title == ""
      assert event.sequence == 0
      assert event.priority == 0
      assert event.privacy == "public"
      assert event.free_busy_status == "busy"
      assert event.show_without_time == false
      assert event.description_content_type == "text/plain"
    end
  end

  describe "sub-objects" do
    test "participants decode into a map keyed by id" do
      json = ~s({
        "@type": "Event", "uid": "e",
        "participants": {
          "dG9tQGZvb2Jhci5xlLmNvbQ": {
            "@type": "Participant",
            "name": "Tom Tool",
            "email": "tom@foobar.example.com",
            "roles": {"attendee": true},
            "participationStatus": "accepted"
          }
        }
      })

      assert {:ok, event} = JSCalendar.decode(json)
      assert %{"dG9tQGZvb2Jhci5xlLmNvbQ" => %Participant{} = tom} = event.participants
      assert tom.name == "Tom Tool"
      assert tom.participation_status == "accepted"
    end

    test "a String[Boolean] set reads as a MapSet" do
      json = ~s({"@type":"Event","uid":"e","keywords":{"talk":true,"elixir":true}})

      assert {:ok, event} = JSCalendar.decode(json)
      assert event.keywords == MapSet.new(["elixir", "talk"])
      assert "elixir" in event.keywords
    end

    test "a set whose values are not all true is malformed" do
      json = ~s({"@type":"Event","uid":"e","keywords":{"talk":false}})

      assert {:error, {Event, "keywords", {:invalid_string_set, _}}} = JSCalendar.decode(json)
    end

    test "locations decode with their links" do
      json = ~s({
        "@type": "Event", "uid": "e",
        "locations": {
          "c0c344fe": {
            "@type": "Location",
            "name": "Conference Room 101",
            "relativeTo": "start",
            "links": {"l1": {"@type": "Link", "href": "https://example.com/floorplan"}}
          }
        }
      })

      assert {:ok, event} = JSCalendar.decode(json)
      assert %{"c0c344fe" => %Location{} = room} = event.locations
      assert room.name == "Conference Room 101"
      assert room.relative_to == "start"
      assert %{"l1" => %Link{href: "https://example.com/floorplan"}} = room.links
    end

    test "a recurrence rule decodes its parts, byDay included" do
      json = ~s({
        "@type": "Event", "uid": "e",
        "recurrenceRules": [{
          "@type": "RecurrenceRule",
          "frequency": "monthly",
          "byDay": [{"@type": "NDay", "day": "mo", "nthOfPeriod": -1}],
          "count": 12
        }]
      })

      assert {:ok, event} = JSCalendar.decode(json)
      assert [%RecurrenceRule{} = rule] = event.recurrence_rules
      assert rule.frequency == "monthly"
      assert rule.count == 12
      assert [%JSCalendar.NDay{day: "mo", nth_of_period: -1}] = rule.by_day
      # Defaults from the spec, not from the document.
      assert rule.interval == 1
      assert rule.rscale == "gregorian"
      assert rule.first_day_of_week == "mo"
    end
  end

  describe "groups" do
    test "entries decode into events and tasks" do
      json = ~s({
        "@type": "Group", "uid": "g", "title": "A group",
        "entries": [
          {"@type": "Event", "uid": "e1", "title": "An event"},
          {"@type": "Task", "uid": "t1", "title": "A task"}
        ]
      })

      assert {:ok, %Group{} = group} = JSCalendar.decode(json)
      assert [%Event{title: "An event"}, %Task{title: "A task"}] = group.entries
    end

    test "an entry of unknown type is ignored, not rejected or dropped" do
      # RFC 8984 §5.3.1: "Implementations MUST ignore entries of
      # unknown type." Keeping the raw map means a read-modify-write
      # cycle does not delete it.
      json = ~s({
        "@type": "Group", "uid": "g",
        "entries": [
          {"@type": "Event", "uid": "e1"},
          {"@type": "Sandwich", "uid": "s1", "filling": "cheese"}
        ]
      })

      assert {:ok, group} = JSCalendar.decode(json)
      assert [%Event{}, %{"@type" => "Sandwich", "filling" => "cheese"}] = group.entries

      {:ok, round_tripped} = JSCalendar.encode(group)
      assert round_tripped =~ "Sandwich"
      assert round_tripped =~ "cheese"
    end
  end

  describe "encoding" do
    test "a round trip preserves every property" do
      assert {:ok, event} = JSCalendar.decode(@simple_event)
      assert {:ok, json} = JSCalendar.encode(event)
      assert {:ok, again} = JSCalendar.decode(json)

      assert again == event
    end

    test "properties at their default are not written back" do
      # Their absence already says the same thing, so a document does
      # not grow each time it is read and rewritten.
      assert {:ok, event} = JSCalendar.decode(~s({"@type":"Event","uid":"e"}))
      map = JSCalendar.to_map(event)

      refute Map.has_key?(map, "title")
      refute Map.has_key?(map, "sequence")
      refute Map.has_key?(map, "privacy")
      assert map["uid"] == "e"
      assert map["@type"] == "Event"
    end

    test "encoding is idempotent" do
      assert {:ok, event} = JSCalendar.decode(@simple_event)
      assert {:ok, once} = JSCalendar.encode(event)
      assert {:ok, decoded} = JSCalendar.decode(once)
      assert {:ok, twice} = JSCalendar.encode(decoded)

      assert once == twice
    end

    test "a MapSet is written back as an object of trues" do
      event = %Event{uid: "e", keywords: MapSet.new(["elixir"])}

      assert JSCalendar.to_map(event)["keywords"] == %{"elixir" => true}
    end

    test "date-times are written in the formats RFC 8984 requires" do
      event = %Event{
        uid: "e",
        start: ~N[2026-06-02 09:00:00],
        updated: ~U[2026-06-01 08:00:00Z]
      }

      map = JSCalendar.to_map(event)

      assert map["start"] == "2026-06-02T09:00:00"
      assert map["updated"] == "2026-06-01T08:00:00Z"
    end
  end

  describe "unknown properties survive" do
    test "a vendor extension round-trips untouched" do
      json = ~s({"@type":"Event","uid":"e","example.com:mood":"cheerful"})

      assert {:ok, event} = JSCalendar.decode(json)
      assert event.extra == %{"example.com:mood" => "cheerful"}

      assert {:ok, encoded} = JSCalendar.encode(event)
      decoded = :json.decode(encoded)
      assert decoded["example.com:mood"] == "cheerful"
    end

    test "a property added by a later revision is not dropped" do
      json = ~s({"@type":"Event","uid":"e","somethingNewIn2030":{"nested":[1,2,3]}})

      assert {:ok, event} = JSCalendar.decode(json)
      assert {:ok, encoded} = JSCalendar.encode(event)
      decoded = :json.decode(encoded)

      assert decoded["somethingNewIn2030"] == %{"nested" => [1, 2, 3]}
    end

    test "@type is not duplicated into extra" do
      assert {:ok, event} = JSCalendar.decode(~s({"@type":"Event","uid":"e"}))

      refute Map.has_key?(event.extra, "@type")
    end
  end

  describe "events" do
    test "duration defaults to PT0S, as the RFC says" do
      assert {:ok, event} = JSCalendar.decode(~s({"@type":"Event","uid":"e"}))

      assert event.duration == nil
      assert Event.duration(event) == %Duration{}
    end

    test "the end is derived from start plus duration" do
      assert {:ok, event} = JSCalendar.decode(@simple_event)

      assert Event.ends_at(event) == ~N[2020-01-15 14:00:00]
    end

    test "an event with no start has no end" do
      assert Event.ends_at(%Event{}) == nil
    end
  end

  describe "alerts" do
    test "an offset trigger decodes into a struct" do
      json = ~s({
        "@type": "Event", "uid": "e",
        "alerts": {
          "a1": {
            "@type": "Alert",
            "trigger": {"@type": "OffsetTrigger", "offset": "-PT15M", "relativeTo": "start"}
          }
        }
      })

      assert {:ok, event} = JSCalendar.decode(json)
      assert %{"a1" => %JSCalendar.Alert{} = alert} = event.alerts
      assert %JSCalendar.OffsetTrigger{relative_to: "start"} = alert.trigger
      assert alert.trigger.offset == %Duration{minute: -15}
    end

    test "an absolute trigger decodes into a struct" do
      json = ~s({
        "@type": "Event", "uid": "e",
        "alerts": {"a1": {"@type": "Alert",
          "trigger": {"@type": "AbsoluteTrigger", "when": "2026-06-02T08:45:00Z"}}}
      })

      assert {:ok, event} = JSCalendar.decode(json)
      assert %{"a1" => alert} = event.alerts
      assert %JSCalendar.AbsoluteTrigger{when: ~U[2026-06-02 08:45:00Z]} = alert.trigger
    end

    test "an unknown trigger kind is kept, and round-trips" do
      json = ~s({
        "@type": "Event", "uid": "e",
        "alerts": {"a1": {"@type": "Alert",
          "trigger": {"@type": "TelepathyTrigger", "intensity": "gentle"}}}
      })

      assert {:ok, event} = JSCalendar.decode(json)
      assert %{"a1" => alert} = event.alerts
      assert alert.trigger == %{"@type" => "TelepathyTrigger", "intensity" => "gentle"}

      assert {:ok, encoded} = JSCalendar.encode(event)
      assert encoded =~ "TelepathyTrigger"
      assert encoded =~ "gentle"
    end
  end

  describe "explicit nulls" do
    test "a null property means the same as an absent one" do
      # RFC 8984 uses explicit nulls — `"timeZone": null` is how an
      # object says it floats. `:json` decodes those to the atom
      # `:null`, which must not reach a struct field.
      json = ~s({"@type":"Event","uid":"e","timeZone":null,"recurrenceIdTimeZone":null})

      assert {:ok, event} = JSCalendar.decode(json)
      assert event.time_zone == nil
      assert event.recurrence_id_time_zone == nil
    end

    test "a null inside an unknown property round-trips as null" do
      json = ~s({"@type":"Event","uid":"e","example.com:x":{"y":null}})

      assert {:ok, event} = JSCalendar.decode(json)
      assert {:ok, encoded} = JSCalendar.encode(event)

      assert :json.decode(encoded)["example.com:x"] == %{"y" => :null}
      assert encoded =~ ~s("y":null)
    end
  end

  describe "patch objects" do
    test "a pointer that is a prefix of another is rejected" do
      patch = %{"locations" => %{}, "locations/mlab/title" => "Room 2"}

      assert {:error, {:overlapping_pointers, "locations", "locations/mlab/title"}} =
               Patch.validate(patch)
    end

    test "a sibling that merely shares a string prefix is not an overlap" do
      assert :ok = Patch.validate(%{"alert" => 1, "alerts" => 2})
    end

    test "nothing is applied when any pointer fails" do
      target = %{"title" => "Standup", "start" => "2026-06-01T09:00:00"}

      assert {:error, {:missing_parent, "locations/mlab/title"}} =
               Patch.apply(target, %{
                 "title" => "Retro",
                 "locations/mlab/title" => "Room 2"
               })
    end

    test "a pointer into an array is rejected rather than splicing" do
      target = %{"recurrenceRules" => [%{"frequency" => "weekly"}]}

      assert {:error, {:points_into_array, "recurrenceRules/0/frequency"}} =
               Patch.apply(target, %{"recurrenceRules/0/frequency" => "daily"})
    end

    test "null removes and is a no-op when the property is absent" do
      assert {:ok, %{"title" => "Standup"}} =
               Patch.apply(%{"title" => "Standup", "color" => "red"}, %{"color" => nil})

      assert {:ok, %{"title" => "Standup"}} =
               Patch.apply(%{"title" => "Standup"}, %{"color" => :null})
    end

    test "decoding validates every patch in the map" do
      json = ~s({"@type":"Event","recurrenceOverrides":{"2020-01-08T09:00:00":{"a":1,"a/b":2}}})

      assert {:error,
              {JSCalendar.Event, "recurrenceOverrides", {:overlapping_pointers, "a", "a/b"}}} =
               JSCalendar.decode(json)
    end
  end

  describe "recurrence overrides" do
    # RFC 8984 §6.9 — Calculus I. A weekly lecture with an extra
    # introductory session, one cancelled week, and an exam that moves.
    setup do
      json = """
      {
        "@type": "Event",
        "uid": "calculus-i",
        "title": "Calculus I",
        "start": "2020-01-08T09:00:00",
        "timeZone": "Europe/London",
        "duration": "PT1H30M",
        "locations": {
          "mlab": {"@type": "Location", "name": "Math lab room 1"}
        },
        "recurrenceRules": [
          {"@type": "RecurrenceRule", "frequency": "weekly", "until": "2020-06-24T09:00:00"}
        ],
        "recurrenceOverrides": {
          "2020-01-07T14:00:00": {"title": "Introduction to Calculus I (optional)"},
          "2020-04-01T09:00:00": {"excluded": true},
          "2020-06-25T09:00:00": {
            "title": "Calculus I Exam",
            "start": "2020-06-25T10:00:00",
            "duration": "PT2H",
            "locations": {"auditorium": {"@type": "Location", "name": "Big Auditorium"}}
          }
        }
      }
      """

      {:ok, event} = JSCalendar.decode(json)
      %{event: event}
    end

    test "the override table decodes with date-time keys", %{event: event} do
      assert Occurrence.overridden(event) == [
               ~N[2020-01-07 14:00:00],
               ~N[2020-04-01 09:00:00],
               ~N[2020-06-25 09:00:00]
             ]
    end

    test "an unoverridden occurrence inherits everything but its start", %{event: event} do
      assert {:ok, occurrence} = Occurrence.at(event, ~N[2020-01-15 09:00:00])

      assert occurrence.start == ~N[2020-01-15 09:00:00]
      assert occurrence.title == "Calculus I"
      assert occurrence.duration == %Duration{hour: 1, minute: 30}
      assert occurrence.locations["mlab"].name == "Math lab room 1"
    end

    test "an occurrence carries its recurrence id and zone", %{event: event} do
      assert {:ok, occurrence} = Occurrence.at(event, ~N[2020-01-15 09:00:00])

      assert occurrence.recurrence_id == ~N[2020-01-15 09:00:00]
      assert occurrence.recurrence_id_time_zone == "Europe/London"
    end

    test "an occurrence does not itself recur", %{event: event} do
      assert {:ok, occurrence} = Occurrence.at(event, ~N[2020-01-15 09:00:00])

      assert occurrence.recurrence_rules == nil
      assert occurrence.recurrence_overrides == nil
    end

    test "an excluded occurrence is not an error", %{event: event} do
      assert :excluded = Occurrence.at(event, ~N[2020-04-01 09:00:00])
      assert Occurrence.excluded?(event, ~N[2020-04-01 09:00:00])
    end

    test "a patched start wins over the recurrence id", %{event: event} do
      assert {:ok, exam} = Occurrence.at(event, ~N[2020-06-25 09:00:00])

      assert exam.start == ~N[2020-06-25 10:00:00]
      assert exam.recurrence_id == ~N[2020-06-25 09:00:00]
      assert exam.duration == %Duration{hour: 2}
      assert exam.title == "Calculus I Exam"
    end

    test "a replaced map replaces rather than merges", %{event: event} do
      assert {:ok, exam} = Occurrence.at(event, ~N[2020-06-25 09:00:00])

      assert Map.keys(exam.locations) == ["auditorium"]
    end

    test "an additional occurrence needs no rule to produce it", %{event: event} do
      assert {:ok, intro} = Occurrence.at(event, ~N[2020-01-07 14:00:00])

      assert intro.start == ~N[2020-01-07 14:00:00]
      assert intro.title == "Introduction to Calculus I (optional)"
    end

    test "a pointer reaching into a nested object patches in place" do
      json = """
      {
        "@type": "Event", "uid": "team", "start": "2020-01-08T09:00:00",
        "participants": {
          "zoe": {"@type": "Participant", "name": "Zoe", "participationStatus": "accepted"}
        },
        "recurrenceOverrides": {
          "2020-03-04T09:00:00": {"participants/zoe/participationStatus": "declined"}
        }
      }
      """

      {:ok, event} = JSCalendar.decode(json)
      {:ok, occurrence} = Occurrence.at(event, ~N[2020-03-04 09:00:00])

      assert occurrence.participants["zoe"].participation_status == "declined"
      assert occurrence.participants["zoe"].name == "Zoe"
      assert event.participants["zoe"].participation_status == "accepted"
    end

    test "an ignored pointer is skipped, not rejected" do
      json = """
      {
        "@type": "Event", "uid": "keep-me", "title": "Standup",
        "start": "2020-01-08T09:00:00",
        "recurrenceOverrides": {
          "2020-01-15T09:00:00": {"uid": "changed", "title": "Retro"}
        }
      }
      """

      {:ok, event} = JSCalendar.decode(json)
      {:ok, occurrence} = Occurrence.at(event, ~N[2020-01-15 09:00:00])

      assert occurrence.uid == "keep-me"
      assert occurrence.title == "Retro"
    end

    test "a task with no start anchors on its due date" do
      task = %JSCalendar.Task{due: ~N[2020-01-08 17:00:00], title: "File returns"}

      assert {:ok, occurrence} = Occurrence.at(task, ~N[2020-02-08 17:00:00])
      assert occurrence.due == ~N[2020-02-08 17:00:00]
      assert occurrence.start == nil
    end

    test "overrides round-trip through encoding" do
      json = ~s({"@type":"Event","recurrenceOverrides":{"2020-01-08T09:00:00":{"title":"X"}}})

      {:ok, event} = JSCalendar.decode(json)
      {:ok, encoded} = JSCalendar.encode(event)

      assert encoded =~ ~s("2020-01-08T09:00:00":{"title":"X"})
    end
  end

  describe "localizations" do
    test "keys are language tags and values are patches" do
      json = """
      {
        "@type": "Event", "title": "Team meeting", "start": "2020-01-08T09:00:00",
        "localizations": {
          "de": {"title": "Teambesprechung"},
          "fr": {"title": "Réunion d'équipe"}
        }
      }
      """

      {:ok, event} = JSCalendar.decode(json)

      assert event.localizations["de"] == %{"title" => "Teambesprechung"}
      assert Map.keys(event.localizations) |> Enum.sort() == ["de", "fr"]
    end

    test "only title, description and name may be localised" do
      base = %{"title" => "Team meeting", "color" => "red"}
      patch = %{"title" => "Teambesprechung", "color" => "blau"}

      assert {:ok, localised} =
               Patch.apply(base, patch, only: ~w(title description name))

      assert localised == %{"title" => "Teambesprechung", "color" => "red"}
    end
  end

  describe "custom time zones" do
    test "a zone with standard and daylight rules decodes" do
      json = """
      {
        "@type": "Event", "start": "2020-01-08T09:00:00", "timeZone": "/example/Test",
        "timeZones": {
          "/example/Test": {
            "@type": "TimeZone",
            "tzId": "/example/Test",
            "updated": "2020-01-01T00:00:00Z",
            "validUntil": "2030-01-01T00:00:00Z",
            "aliases": {"/example/Alias": true},
            "standard": [{
              "@type": "TimeZoneRule",
              "start": "1998-10-25T03:00:00",
              "offsetFrom": "+0200",
              "offsetTo": "+0100",
              "names": {"CET": true},
              "recurrenceRules": [{
                "@type": "RecurrenceRule", "frequency": "yearly", "byMonth": ["10"]
              }]
            }],
            "daylight": [{
              "@type": "TimeZoneRule",
              "start": "1998-03-29T02:00:00",
              "offsetFrom": "+0100",
              "offsetTo": "+0200",
              "names": {"CEST": true}
            }]
          }
        }
      }
      """

      {:ok, event} = JSCalendar.decode(json)
      zone = event.time_zones["/example/Test"]

      assert zone.tz_id == "/example/Test"
      assert zone.updated == ~U[2020-01-01 00:00:00Z]
      assert zone.aliases == MapSet.new(["/example/Alias"])

      [standard] = zone.standard
      assert standard.start == ~N[1998-10-25 03:00:00]
      assert standard.offset_from == "+0200"
      assert standard.offset_to == "+0100"
      assert standard.names == MapSet.new(["CET"])
      assert [%JSCalendar.RecurrenceRule{frequency: "yearly"}] = standard.recurrence_rules

      [daylight] = zone.daylight
      assert daylight.offset_to == "+0200"
    end

    test "a custom zone round-trips" do
      zone = %TimeZone{
        tz_id: "/example/Test",
        standard: [
          %TimeZoneRule{
            start: ~N[1998-10-25 03:00:00],
            offset_from: "+0200",
            offset_to: "+0100"
          }
        ]
      }

      encoded = TimeZone.to_map(zone)

      assert %{"@type" => "TimeZone", "tzId" => "/example/Test"} = encoded

      assert [%{"@type" => "TimeZoneRule", "start" => "1998-10-25T03:00:00"}] =
               encoded["standard"]

      assert {:ok, ^zone} = TimeZone.from_map(encoded)
    end
  end
end
