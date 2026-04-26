defmodule Athanor.Schema.WatchingToken do
  @moduledoc """
  A STAS token ID explicitly added to the watch list by an admin.

  The indexer only tracks STAS token operations for token IDs in this table.
  Each `token_id` must be unique. For STAS 3.0 issuances, `token_id` is the
  lowercase hex of the 20-byte `protoID` (HASH160 of the issuer/redemption
  address per spec v0.1 §5.2.1 / §14) — NOT the owner PKH.

  Optional STAS 3.0 metadata captured by the indexer at first observation:

    * `canonical_post_op_return` — bytes following `OP_RETURN` in the
      issuance's data attachment (spec §4). Subsequent outputs of the same
      `protoID` MUST be byte-identical here; mismatches are flagged.

    * `freeze_auth` / `confiscate_auth` — 20-byte HASH160 service-field
      authorities populated when the corresponding flag bit is set in the
      issuance frame (spec §5.2.3).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "watching_tokens" do
    field :token_id, :string
    field :symbol, :string
    field :canonical_post_op_return, :binary
    field :freeze_auth, :binary
    field :confiscate_auth, :binary

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @optional_fields ~w(symbol canonical_post_op_return freeze_auth confiscate_auth)a

  @doc """
  Builds a changeset for adding a watched STAS token.

  ## Parameters
    - `watching_token` — existing struct or empty schema
    - `attrs` — map with :token_id (required) and any optional fields

  ## Returns
    An `Ecto.Changeset` with unique constraint on token_id.
  """
  def changeset(watching_token, attrs) do
    watching_token
    |> cast(attrs, [:token_id | @optional_fields])
    |> validate_required([:token_id])
    |> validate_authority_length(:freeze_auth)
    |> validate_authority_length(:confiscate_auth)
    |> unique_constraint(:token_id)
  end

  # Authority fields (when present) must be exactly 20 bytes — the size of
  # a HASH160. Allow nil so admins can register a token before the issuance
  # frame is observed.
  defp validate_authority_length(changeset, field) do
    case get_change(changeset, field) do
      nil -> changeset
      bin when is_binary(bin) and byte_size(bin) == 20 -> changeset
      _ -> add_error(changeset, field, "must be a 20-byte HASH160")
    end
  end
end
