defmodule AlternativeServer.UsersCard do
  use Ecto.Schema
  import Ecto.Changeset

  @foreign_key_type :binary_id

  schema "users_cards" do
    field :count, :integer
    field :user_id, :binary_id
    field :card_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(users_card, attrs) do
    users_card
    |> cast(attrs, [:count, :user_id, :card_id])
    |> validate_required([:count, :user_id, :card_id])
  end
end
