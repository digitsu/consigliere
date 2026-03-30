defmodule Athanor.Schema.WatchingAddress do
  @moduledoc """
  An address explicitly added to the watch list by an admin.

  The indexer only tracks transactions involving addresses in this table.
  Each address must be unique.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "watching_addresses" do
    field :address, :string
    field :name, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Builds a changeset for adding a watched address.

  ## Parameters
    - `watching_address` — existing struct or empty schema
    - `attrs` — map with :address (required) and :name (optional)

  ## Returns
    An `Ecto.Changeset` with unique constraint on address.
  """
  def changeset(watching_address, attrs) do
    watching_address
    |> cast(attrs, [:address, :name])
    |> validate_required([:address])
    |> unique_constraint(:address)
  end
end
