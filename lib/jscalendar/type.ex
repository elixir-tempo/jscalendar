defmodule JSCalendar.Type do
  @moduledoc """
  Reading and writing the value types RFC 8984 defines.

  JSCalendar is JSON, so every value arrives as a string, number,
  boolean, list or map. This module is the single place that decides
  what each becomes in Elixir and how it goes back — so a round trip is
  one pair of functions to reason about rather than a decision repeated
  at every property.

  The mapping is deliberately to standard-library types, not to types
  invented here:

  | JSCalendar | Elixir |
  | --- | --- |
  | `LocalDateTime` | `t:NaiveDateTime.t/0` |
  | `UTCDateTime` | `t:DateTime.t/0` in `Etc/UTC` |
  | `Duration`, `SignedDuration` | `t:Duration.t/0` |
  | `String[Boolean]` | `t:MapSet.t/0` |
  | `Id[Foo]` | `%{String.t() => Foo.t()}` |

  A `String[Boolean]` is a set written as an object whose values are
  all `true`, so it reads back as a `MapSet` — `"attendee" in
  participant.roles` rather than a map lookup against a value that
  carries no information.

  """

  @typedoc "A property's declared JSCalendar type."
  @type spec ::
          :string
          | :boolean
          | :int
          | :unsigned_int
          | :local_date_time
          | :utc_date_time
          | :duration
          | :string_set
          | :string_map
          | :any
          | {:enum, [String.t()]}
          | {:list, spec()}
          | {:object, module()}
          | {:map_of, module()}
          | {:list_of, module()}

  @doc """
  Read a JSON value as `spec`.

  ### Arguments

  * `value` is the decoded JSON value.

  * `spec` is a `t:spec/0` naming the JSCalendar type.

  ### Returns

  * `{:ok, value}` with the Elixir representation; or

  * `{:error, reason}` when the value does not match the type.

  ### Examples

      iex> JSCalendar.Type.decode("2026-06-02T09:00:00", :local_date_time)
      {:ok, ~N[2026-06-02 09:00:00]}

      iex> JSCalendar.Type.decode("PT1H", :duration)
      {:ok, %Duration{hour: 1}}

      iex> JSCalendar.Type.decode(%{"a" => true, "b" => true}, :string_set)
      {:ok, MapSet.new(["a", "b"])}

      iex> JSCalendar.Type.decode("nope", :local_date_time)
      {:error, {:invalid_local_date_time, "nope"}}

  """
  @spec decode(term(), spec()) :: {:ok, term()} | {:error, term()}
  def decode(nil, _spec), do: {:ok, nil}

  # `:json` decodes JSON `null` to the atom `:null`, not to `nil`. RFC
  # 8984 uses explicit nulls — `"timeZone": null` is how an object says
  # it floats — so a null property means the same as an absent one
  # here, and encoding writes neither.
  def decode(:null, _spec), do: {:ok, nil}

  def decode(value, :string) when is_binary(value), do: {:ok, value}
  def decode(value, :boolean) when is_boolean(value), do: {:ok, value}
  def decode(value, :int) when is_integer(value), do: {:ok, value}
  def decode(value, :unsigned_int) when is_integer(value) and value >= 0, do: {:ok, value}
  def decode(value, :any), do: {:ok, value}

  def decode(value, :local_date_time) when is_binary(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, naive} -> {:ok, naive}
      {:error, _reason} -> {:error, {:invalid_local_date_time, value}}
    end
  end

  def decode(value, :utc_date_time) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, DateTime.shift_zone!(datetime, "Etc/UTC")}
      {:error, _reason} -> {:error, {:invalid_utc_date_time, value}}
    end
  end

  def decode(value, :duration) when is_binary(value) do
    case Duration.from_iso8601(value) do
      {:ok, duration} -> {:ok, duration}
      {:error, _reason} -> {:error, {:invalid_duration, value}}
    end
  end

  # RFC 8984 §1.4.10: a set is an object whose values are all `true`.
  # A `false` is not a member that is switched off, it is malformed.
  def decode(value, :string_set) when is_map(value) do
    if Enum.all?(value, fn {key, member} -> is_binary(key) and member == true end) do
      {:ok, value |> Map.keys() |> MapSet.new()}
    else
      {:error, {:invalid_string_set, value}}
    end
  end

  def decode(value, :string_map) when is_map(value) do
    if Enum.all?(value, fn {key, entry} -> is_binary(key) and is_binary(entry) end) do
      {:ok, value}
    else
      {:error, {:invalid_string_map, value}}
    end
  end

  def decode(value, {:enum, allowed}) when is_binary(value) do
    # An unrecognised value is kept rather than rejected: RFC 8984
    # §1.5 reserves the right to extend these vocabularies, and a
    # parser that refuses tomorrow's value cannot read tomorrow's data.
    if value in allowed, do: {:ok, value}, else: {:ok, value}
  end

  def decode(value, {:list, inner}) when is_list(value) do
    collect(value, &decode(&1, inner))
  end

  def decode(value, {:object, module}) when is_map(value) do
    module.from_map(value)
  end

  def decode(value, {:list_of, module}) when is_list(value) do
    collect(value, &module.from_map/1)
  end

  def decode(value, {:map_of, module}) when is_map(value) do
    value
    |> Enum.reduce_while({:ok, %{}}, fn {id, entry}, {:ok, acc} ->
      case module.from_map(entry) do
        {:ok, decoded} -> {:cont, {:ok, Map.put(acc, id, decoded)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  def decode(value, spec), do: {:error, {:invalid_value, spec, value}}

  @doc """
  Write an Elixir value back as JSON for `spec`.

  `nil` is dropped by the caller rather than written as JSON `null`,
  since RFC 8984 distinguishes an absent property from a null one.

  ### Arguments

  * `value` is the Elixir value.

  * `spec` is a `t:spec/0` naming the JSCalendar type.

  ### Returns

  * the JSON-ready value.

  ### Examples

      iex> JSCalendar.Type.encode(~N[2026-06-02 09:00:00], :local_date_time)
      "2026-06-02T09:00:00"

      iex> JSCalendar.Type.encode(MapSet.new(["a"]), :string_set)
      %{"a" => true}

  """
  @spec encode(term(), spec()) :: term()
  def encode(nil, _spec), do: nil

  def encode(%NaiveDateTime{} = value, :local_date_time) do
    value |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_iso8601()
  end

  def encode(%DateTime{} = value, :utc_date_time) do
    value |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end

  def encode(%Duration{} = value, :duration), do: Duration.to_iso8601(value)

  def encode(%MapSet{} = value, :string_set) do
    Map.new(value, fn member -> {member, true} end)
  end

  def encode(value, {:list, inner}) when is_list(value) do
    Enum.map(value, &encode(&1, inner))
  end

  def encode(value, {:object, module}), do: module.to_map(value)

  def encode(value, {:list_of, module}) when is_list(value) do
    Enum.map(value, &module.to_map/1)
  end

  def encode(value, {:map_of, module}) when is_map(value) do
    Map.new(value, fn {id, entry} -> {id, module.to_map(entry)} end)
  end

  def encode(value, _spec), do: value

  defp collect(values, decoder) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case decoder.(value) do
        {:ok, decoded} -> {:cont, {:ok, [decoded | acc]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, decoded} -> {:ok, Enum.reverse(decoded)}
      {:error, _reason} = error -> error
    end
  end
end
