defmodule Consigliere.Schema.AddressHistory do
  @moduledoc """
  Records the transaction history for a watched address.

  Each entry represents a single directional flow: an `in` (received) or
  `out` (sent) event for an address. Used for paginated history queries.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "address_histories" do
    field :address, :string
    field :txid, :string
    field :direction, :string
    field :satoshis, :integer
    field :token_id, :string
    field :block_height, :integer
    field :timestamp, :integer

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @required_fields ~w(address txid direction satoshis timestamp)a
  @optional_fields ~w(token_id block_height)a

  @doc """
  Builds a changeset for inserting an address history entry.

  ## Parameters
    - `history` — existing struct or empty schema
    - `attrs` — map of field values

  ## Returns
    An `Ecto.Changeset` validating direction is "in" or "out".
  """
  def changeset(history, attrs) do
    history
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:direction, ~w(in out))
  end
end
