defmodule JSCalendar.Patch do
  @moduledoc """
  A set of changes to a JSCalendar object
  ([RFC 8984 §1.4.9](https://www.rfc-editor.org/rfc/rfc8984.html#section-1.4.9)).

  A PatchObject is how JSCalendar says "the same as that, but different
  here". Each key is a path and each value is what to put there, so a
  recurring event that moves one week states only the move rather than
  restating the event:

      %{"start" => "2020-01-22T14:00:00", "locations/room/name" => "Room B"}

  Paths are a restricted [JSON Pointer](https://www.rfc-editor.org/rfc/rfc6901),
  with the leading `/` implied. A `null` value removes the property; any
  other value sets it.

  ### Why this is a module and not a map lookup

  Four rules decide whether a patch may be applied at all, and getting
  them wrong corrupts the object rather than failing loudly:

  1. A pointer must not reach inside an **array**. Arrays are replaced
     whole, never spliced — there is no way to say "insert at index 2"
     and no way to mean it unambiguously if two patches disagree.

  2. Every part **before** the last must already exist. A patch is a
     change to something, not a way to conjure structure.

  3. No pointer may be a **prefix** of another. `alerts` and
     `alerts/1/offset` in one patch have no defined order, so the
     result would depend on which was applied first.

  4. `null` may only remove a property that is **optional**.

  The specification is emphatic about what happens when one fails:
  implementations MUST reject the patch **in its entirety** and MUST
  NOT apply it partially. A half-applied patch is an object that never
  existed and that nobody asked for, so `apply/2` builds the result
  and only returns it once every pointer has succeeded.

  """

  @typedoc "An unordered set of changes, keyed by path."
  @type t :: %{optional(String.t()) => term()}

  @doc """
  Apply `patch` to `target`.

  ### Arguments

  * `target` is the map being patched — a decoded JSCalendar object.

  * `patch` is a `t:t/0`.

  ### Options

  * `:ignore` is a list of path prefixes to skip rather than reject.
    RFC 8984 requires certain pointers to be *ignored* in
    `recurrenceOverrides` and `localizations`, which is different from
    rejecting them.

  * `:only` is a list of path suffixes to keep; anything else is
    skipped. `localizations` allows only `title`, `description` and
    `name`.

  ### Returns

  * `{:ok, patched}`; or

  * `{:error, reason}` when any pointer is invalid, in which case
    nothing has been applied.

  ### Examples

      iex> JSCalendar.Patch.apply(%{"title" => "Standup"}, %{"title" => "Retro"})
      {:ok, %{"title" => "Retro"}}

      iex> JSCalendar.Patch.apply(%{"title" => "Standup", "color" => "red"}, %{"color" => nil})
      {:ok, %{"title" => "Standup"}}

      iex> JSCalendar.Patch.apply(%{"a" => %{"b" => 1}}, %{"a/b" => 2})
      {:ok, %{"a" => %{"b" => 2}}}

      iex> JSCalendar.Patch.apply(%{}, %{"a/b" => 2})
      {:error, {:missing_parent, "a/b"}}

      iex> JSCalendar.Patch.apply(%{"a" => [1, 2]}, %{"a/0" => 9})
      {:error, {:points_into_array, "a/0"}}

  """
  @spec apply(map(), t(), keyword()) :: {:ok, map()} | {:error, term()}
  def apply(target, patch, options \\ [])

  def apply(target, patch, options) when is_map(target) and is_map(patch) do
    with :ok <- validate(patch) do
      patch
      |> Enum.reject(&skip?(&1, options))
      |> Enum.reduce_while({:ok, target}, &apply_one/2)
    end
  end

  def apply(target, _patch, _options), do: {:error, {:not_an_object, target}}

  @doc """
  Check that `patch` is well formed, without applying it.

  Only the rules that can be decided from the patch alone are checked
  here — whether a parent exists, and whether a pointer reaches into an
  array, depend on the object being patched and are settled by
  `apply/3`.

  ### Arguments

  * `patch` is a `t:t/0`.

  ### Returns

  * `:ok`; or

  * `{:error, {:overlapping_pointers, a, b}}` when one pointer is a
    prefix of another.

  ### Examples

      iex> JSCalendar.Patch.validate(%{"title" => "Retro", "color" => "red"})
      :ok

      iex> JSCalendar.Patch.validate(%{"alerts" => %{}, "alerts/1/offset" => "-PT5M"})
      {:error, {:overlapping_pointers, "alerts", "alerts/1/offset"}}

  """
  @spec validate(t()) :: :ok | {:error, term()}
  def validate(patch) when is_map(patch) do
    pointers = patch |> Map.keys() |> Enum.sort()

    Enum.reduce_while(pointers, :ok, fn pointer, :ok ->
      case Enum.find(pointers, &prefix_of?(pointer, &1)) do
        nil -> {:cont, :ok}
        other -> {:halt, {:error, {:overlapping_pointers, pointer, other}}}
      end
    end)
  end

  defp apply_one({pointer, value}, {:ok, target}) do
    case put(target, segments(pointer), value, pointer) do
      {:ok, patched} -> {:cont, {:ok, patched}}
      {:error, _reason} = error -> {:halt, error}
    end
  end

  # Segment-wise, not string-wise: `alert` is not a prefix of `alerts`,
  # but `alerts` is a prefix of `alerts/1`.
  defp prefix_of?(pointer, other) do
    pointer != other and String.starts_with?(other, pointer <> "/")
  end

  defp segments(pointer), do: String.split(pointer, "/")

  defp skip?({pointer, _value}, options) do
    ignored?(pointer, Keyword.get(options, :ignore, [])) or
      not permitted?(pointer, Keyword.get(options, :only))
  end

  defp ignored?(pointer, prefixes) do
    Enum.any?(prefixes, &(pointer == &1 or String.starts_with?(pointer, &1 <> "/")))
  end

  defp permitted?(_pointer, nil), do: true

  defp permitted?(pointer, suffixes) do
    last = pointer |> segments() |> List.last()

    last in suffixes
  end

  # Walk to the parent, then set or remove. Anything missing on the way
  # is rule 2 broken; anything that turns out to be a list is rule 1.
  defp put(target, [key], value, _pointer) when is_map(target) do
    if removal?(value) do
      {:ok, Map.delete(target, key)}
    else
      {:ok, Map.put(target, key, value)}
    end
  end

  defp put(target, [key | rest], value, pointer) when is_map(target) do
    case Map.fetch(target, key) do
      {:ok, child} when is_map(child) ->
        with {:ok, patched} <- put(child, rest, value, pointer) do
          {:ok, Map.put(target, key, patched)}
        end

      {:ok, child} when is_list(child) ->
        {:error, {:points_into_array, pointer}}

      {:ok, _leaf} ->
        {:error, {:missing_parent, pointer}}

      :error ->
        {:error, {:missing_parent, pointer}}
    end
  end

  defp put(target, _segments, _value, pointer) when is_list(target) do
    {:error, {:points_into_array, pointer}}
  end

  defp put(_target, _segments, _value, pointer), do: {:error, {:missing_parent, pointer}}

  # `:json` decodes JSON null to the atom `:null`; a hand-built patch is
  # more likely to use `nil`. Both mean remove.
  defp removal?(nil), do: true
  defp removal?(:null), do: true
  defp removal?(_value), do: false
end
