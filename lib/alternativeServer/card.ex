defmodule AlternativeServer.Card do
  use Ecto.Schema
  import Ecto.Changeset

  schema "cards" do
    field :name, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(card, attrs) do
    card
    |> cast(attrs, [:name])
    |> validate_required([:name])
  end
end
