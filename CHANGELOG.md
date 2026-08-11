# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

* First release. Reads and writes [RFC 8984](https://www.rfc-editor.org/rfc/rfc8984.html) JSCalendar — `Event`, `Task` and `Group`, with the `Location`, `VirtualLocation`, `Link`, `Relation`, `Participant`, `RecurrenceRule`, `NDay` and `Alert` sub-objects. `JSCalendar.decode/1` dispatches on `@type`; `JSCalendar.encode/1` writes it back.

* No dependencies. Erlang's `:json` and Elixir's `Duration` are both standard library, so values map to standard types — `LocalDateTime` to `NaiveDateTime`, `UTCDateTime` to `DateTime`, and a `String[Boolean]` set to a `MapSet`. Requires Elixir 1.17 and OTP 27.

* Unknown properties round-trip. Anything the specification does not name is kept in each object's `extra` and written back untouched, and a group entry of an unrecognised type is ignored rather than rejected or dropped, as RFC 8984 §5.3.1 requires.

* Properties equal to their RFC default are omitted on encode, so a document does not grow each time it is read and rewritten and encoding is idempotent.

* `JSCalendar.Patch` implements RFC 8984 §1.4.9 PatchObjects with `apply/3` and `validate/1`. An invalid pointer rejects the whole patch rather than applying part of it, and `:ignore` and `:only` express the prefixes and suffixes the specification restricts particular properties to.

* `JSCalendar.Occurrence.at/2` builds one instance of a recurring object from its recurrence id, applying any override. It answers `:excluded` distinctly from `{:error, _}`, and `overridden/1` lists the ids an object varies.

* `recurrenceOverrides` and `localizations` are typed as patch maps — keyed by recurrence id and language tag respectively — and `timeZones` as `JSCalendar.TimeZone` with `JSCalendar.TimeZoneRule` standard and daylight rules.
