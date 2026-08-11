defmodule JSCalendar.Occurrence do
  @moduledoc """
  One instance of a recurring object
  ([RFC 8984 §4.3.5](https://www.rfc-editor.org/rfc/rfc8984.html#section-4.3.5)).

  A recurring object is a base plus a rule plus a table of exceptions.
  Expanding the rule gives you a list of *recurrence ids* — local
  date-times — and this module turns one of those back into an object:
  the base, shifted to that moment, with any override applied.

      JSCalendar.Occurrence.at(standup, ~N[2026-06-04 09:00:00])
      #=> {:ok, %JSCalendar.Event{start: ~N[2026-06-04 09:00:00], ...}}

  Three things happen that a plain patch would not do:

  * The **anchor moves**. An occurrence inherits everything except its
    `start` — or, for a task with no start, its `due` — which becomes
    the recurrence id. A patch may then override even that, and the
    patch wins.

  * The **recurrence machinery is stripped**. §4.3.1 forbids an object
    with a `recurrenceId` from also carrying `recurrenceRules` or
    `recurrenceOverrides`, so an occurrence is a single object rather
    than a recurring one that recurs again.

  * Some pointers are **ignored rather than rejected**. An override may
    not change a `uid`, a `prodId`, or the rules that generated it; the
    RFC's word is *ignored*, so such a patch still applies — minus
    those pointers — rather than failing.

  Exclusion is a separate answer, not an empty one:

      JSCalendar.Occurrence.at(standup, ~N[2026-06-05 09:00:00])
      #=> :excluded

  A caller expanding a rule has to distinguish "this occurrence was
  cancelled" from "this occurrence could not be built", and a tuple
  that could mean either would make that impossible.

  """

  alias JSCalendar.Patch
  alias JSCalendar.Type

  # RFC 8984 §4.3.5. These name what an occurrence is *of*, so an
  # override that tried to change them would be describing a different
  # object rather than a variation of this one.
  @ignored ~w(
    @type excludedRecurrenceRules method privacy prodId recurrenceId
    recurrenceIdTimeZone recurrenceOverrides recurrenceRules relatedTo
    replyTo sentBy timeZones uid
  )

  # Not ignored — removed. §4.3.1 makes these illegal on an occurrence
  # rather than merely unpatchable.
  @stripped ~w(recurrenceRules excludedRecurrenceRules recurrenceOverrides)

  @doc """
  Build the occurrence of `object` at `recurrence_id`.

  ### Arguments

  * `object` is a recurring `t:JSCalendar.Event.t/0` or
    `t:JSCalendar.Task.t/0`.

  * `recurrence_id` is a `t:NaiveDateTime.t/0` produced by the object's
    recurrence rules, or a key of its `recurrence_overrides` that the
    rules did not produce — an additional occurrence, the equivalent of
    an iCalendar `RDATE`.

  ### Returns

  * `{:ok, occurrence}` — the same struct type as `object`, carrying
    `recurrence_id` and `recurrence_id_time_zone`; or

  * `:excluded` when the override sets `excluded` to `true`; or

  * `{:error, reason}` when the override is not a valid patch.

  ### Examples

      iex> standup = %JSCalendar.Event{
      ...>   uid: "a", start: ~N[2026-06-01 09:00:00], time_zone: "Australia/Sydney",
      ...>   recurrence_overrides: %{~N[2026-06-03 09:00:00] => %{"title" => "Retro"}}}
      iex> {:ok, occurrence} = JSCalendar.Occurrence.at(standup, ~N[2026-06-03 09:00:00])
      iex> {occurrence.start, occurrence.title, occurrence.recurrence_id}
      {~N[2026-06-03 09:00:00], "Retro", ~N[2026-06-03 09:00:00]}

      iex> standup = %JSCalendar.Event{
      ...>   start: ~N[2026-06-01 09:00:00],
      ...>   recurrence_overrides: %{~N[2026-06-03 09:00:00] => %{"excluded" => true}}}
      iex> JSCalendar.Occurrence.at(standup, ~N[2026-06-03 09:00:00])
      :excluded

  """
  @spec at(struct(), NaiveDateTime.t()) :: {:ok, struct()} | :excluded | {:error, term()}
  def at(%module{} = object, %NaiveDateTime{} = recurrence_id) do
    patch = object |> overrides() |> Map.get(recurrence_id, %{})

    if excluded?(patch) do
      :excluded
    else
      with {:ok, patched} <- Patch.apply(inherit(object, recurrence_id), patch, ignore: @ignored) do
        module.from_map(patched)
      end
    end
  end

  @doc """
  The recurrence ids `object` overrides, in chronological order.

  Includes both variations on rule-generated occurrences and additional
  ones the rules do not produce — telling those apart needs the rules
  expanded, which is the caller's business, not this module's.

  ### Arguments

  * `object` is a `t:JSCalendar.Event.t/0` or `t:JSCalendar.Task.t/0`.

  ### Returns

  * a list of `t:NaiveDateTime.t/0`.

  ### Examples

      iex> event = %JSCalendar.Event{recurrence_overrides: %{
      ...>   ~N[2026-06-05 09:00:00] => %{"excluded" => true},
      ...>   ~N[2026-06-03 09:00:00] => %{"title" => "Retro"}}}
      iex> JSCalendar.Occurrence.overridden(event)
      [~N[2026-06-03 09:00:00], ~N[2026-06-05 09:00:00]]

  """
  @spec overridden(struct()) :: [NaiveDateTime.t()]
  def overridden(object) do
    object |> overrides() |> Map.keys() |> Enum.sort(NaiveDateTime)
  end

  @doc """
  Whether the occurrence at `recurrence_id` is excluded.

  ### Arguments

  * `object` is a `t:JSCalendar.Event.t/0` or `t:JSCalendar.Task.t/0`.

  * `recurrence_id` is a `t:NaiveDateTime.t/0`.

  ### Returns

  * `true` or `false`.

  ### Examples

      iex> event = %JSCalendar.Event{
      ...>   recurrence_overrides: %{~N[2026-06-05 09:00:00] => %{"excluded" => true}}}
      iex> JSCalendar.Occurrence.excluded?(event, ~N[2026-06-05 09:00:00])
      true

      iex> JSCalendar.Occurrence.excluded?(%JSCalendar.Event{}, ~N[2026-06-05 09:00:00])
      false

  """
  @spec excluded?(struct(), NaiveDateTime.t()) :: boolean()
  def excluded?(object, %NaiveDateTime{} = recurrence_id) do
    object |> overrides() |> Map.get(recurrence_id, %{}) |> excluded?()
  end

  defp overrides(object), do: Map.get(object, :recurrence_overrides) || %{}

  # `:json` gives the atom `:null` for a JSON null, which is not `true`
  # either way, so only an explicit `true` excludes.
  defp excluded?(patch) when is_map(patch), do: Map.get(patch, "excluded") == true
  defp excluded?(_patch), do: false

  # The base, as JSON, with the recurrence machinery removed and the
  # anchor moved. A patch of `start` then overwrites this, which is the
  # precedence §4.3.5 specifies.
  defp inherit(%module{} = object, recurrence_id) do
    moment = Type.encode(recurrence_id, :local_date_time)

    object
    |> module.to_map()
    |> Map.drop(@stripped)
    |> Map.put(anchor(object), moment)
    |> Map.put("recurrenceId", moment)
    |> put_recurrence_zone(object)
  end

  # A task with no start recurs by its due date, so that is what the
  # recurrence id shifts. Anything else anchors on `start`.
  defp anchor(%JSCalendar.Task{start: nil, due: %NaiveDateTime{}}), do: "due"
  defp anchor(_object), do: "start"

  # §4.3.2 pairs the two: the zone must be set when the id is, and must
  # not be when it is not. A floating base stays floating.
  defp put_recurrence_zone(map, object) do
    case Map.get(object, :time_zone) do
      nil -> map
      zone -> Map.put(map, "recurrenceIdTimeZone", zone)
    end
  end
end
