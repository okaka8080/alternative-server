defmodule AlternativeServer.UsersDecks do
  use Ecto.Schema
  import Ecto.Changeset

  @foreign_key_type :binary_id

  schema "users_decks" do

    field :user_id, :binary_id
    field :deck_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(users_decks, attrs) do
    users_decks
    |> cast(attrs, [])
    |> validate_required([])
  end
end
