defmodule Athanor.Schema.Utxo do
  @moduledoc """
  Represents an unspent (or spent) transaction output.

  Each UTXO is uniquely identified by `(txid, vout)`. When a UTXO is consumed,
  `is_spent` is set to true and `spent_txid` records the consuming transaction.
  Token outputs carry `token_id` and `token_type` ("stas" or "stas3").

  For STAS 3.0 outputs, `token_id` is the hex-encoded `protoID` (HASH160 of
  the issuer/redemption address, per spec v0.1 §5.2.1 / §14) — NOT the owner
  PKH. `stas3_op` records the spendType class of the spending input, when
  observed, drawn from the set returned by `Athanor.Tokens.SpendType`
  (`transfer` / `freeze_unfreeze` / `confiscation` / `swap_cancel`).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @stas3_ops ~w(transfer freeze_unfreeze confiscation swap_cancel)

  schema "utxos" do
    field :txid, :binary
    field :vout, :integer
    field :address, :string
    field :satoshis, :integer
    field :script_hex, :string
    field :token_id, :string
    field :token_type, :string
    field :stas3_op, :string
    field :is_spent, :boolean, default: false
    field :spent_txid, :binary
    field :block_height, :integer

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(txid vout address satoshis script_hex)a
  @optional_fields ~w(token_id token_type stas3_op is_spent spent_txid block_height)a

  @doc """
  Builds a changeset for inserting or updating a UTXO record.

  ## Parameters
    - `utxo` — existing struct or empty schema
    - `attrs` — map of field values

  ## Returns
    An `Ecto.Changeset` with validations applied. Enforces unique (txid, vout).
  """
  def changeset(utxo, attrs) do
    utxo
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:vout, greater_than_or_equal_to: 0)
    |> validate_number(:satoshis, greater_than_or_equal_to: 0)
    |> validate_inclusion(:token_type, ~w(stas stas3), message: "must be stas or stas3")
    |> validate_inclusion(:stas3_op, @stas3_ops,
      message: "must be one of #{Enum.join(@stas3_ops, ", ")}"
    )
    |> unique_constraint([:txid, :vout], name: :utxos_txid_vout_index)
  end
end
