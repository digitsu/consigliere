defmodule Athanor.Schema.WatchingToken do
  @moduledoc """
  A STAS token ID explicitly added to the watch list by an admin.

  The indexer only tracks STAS token operations for token IDs in this table.
  Each token_id must be unique.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "watching_tokens" do
    field :token_id, :string
    field :symbol, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Builds a changeset for adding a watched STAS token.

  ## Parameters
    - `watching_token` — existing struct or empty schema
    - `attrs` — map with :token_id (required) and :symbol (optional)

  ## Returns
    An `Ecto.Changeset` with unique constraint on token_id.
  """
  def changeset(watching_token, attrs) do
    watching_token
    |> cast(attrs, [:token_id, :symbol])
    |> validate_required([:token_id])
    |> unique_constraint(:token_id)
  end
end
