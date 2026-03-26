defmodule Consigliere.Schema.BlockProcessContext do
  @moduledoc """
  Tracks which blocks have been processed by the indexer.

  The primary key `id` is the block hash (text), not an auto-generated UUID.
  `height` has a unique index for fast tip lookups. Used for reorg detection
  and ensuring blocks are processed exactly once.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :binary_id

  schema "block_process_contexts" do
    field :height, :integer
    field :processed_at, :utc_datetime
  end

  @doc """
  Builds a changeset for recording a processed block.

  ## Parameters
    - `context` — existing struct or empty schema
    - `attrs` — map with :id (block hash), :height, and :processed_at

  ## Returns
    An `Ecto.Changeset` with unique constraint on height.
  """
  def changeset(context, attrs) do
    context
    |> cast(attrs, [:id, :height, :processed_at])
    |> validate_required([:id, :height, :processed_at])
    |> unique_constraint(:height)
  end
end
