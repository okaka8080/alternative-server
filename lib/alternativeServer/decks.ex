defmodule AlternativeServer.Decks do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "decks" do
    field :card_list, {:array, :integer}

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(decks, attrs) do
    decks
    |> cast(attrs, [:card_list])
    |> validate_required([:card_list])
  end
end
