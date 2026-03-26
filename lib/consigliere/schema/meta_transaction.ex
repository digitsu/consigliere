defmodule Consigliere.Schema.MetaTransaction do
  @moduledoc """
  Stores transaction metadata for watched addresses/tokens.

  The `txid` is stored as a 32-byte binary for efficient lookups.
  `addresses` and `token_ids` are PostgreSQL text arrays with GIN indexes
  for fast containment queries (e.g. "find all txs involving address X").
  `metadata` is a JSONB column for flexible extra fields.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "meta_transactions" do
    field :txid, :binary
    field :hex, :string
    field :block_hash, :binary
    field :block_height, :integer
    field :timestamp, :integer
    field :is_confirmed, :boolean, default: false
    field :addresses, {:array, :string}, default: []
    field :token_ids, {:array, :string}, default: []
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(txid hex timestamp)a
  @optional_fields ~w(block_hash block_height is_confirmed addresses token_ids metadata)a

  @doc """
  Builds a changeset for inserting or updating a meta_transaction record.

  ## Parameters
    - `meta_tx` — existing struct or empty schema
    - `attrs` — map of field values

  ## Returns
    An `Ecto.Changeset` with validations applied.
  """
  def changeset(meta_tx, attrs) do
    meta_tx
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:txid)
  end
end
