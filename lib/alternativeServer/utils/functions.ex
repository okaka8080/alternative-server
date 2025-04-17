defmodule AlternativeServer.Functions do
  require Logger

  def list_to_map(list) do
    Enum.chunk_every(list, 2)
    |> Enum.into(%{}, fn [key, value] ->
      {String.to_atom(key), parse_value(value)}
    end)
  end

  defp parse_value(value) do
    case Integer.parse(value) do
      {int, ""} ->
        int

      :error ->
        case value do
          "true" -> true
          "false" -> false
          _ -> value
        end
    end
  end
end
