defmodule Consigliere.Schema.Broadcast do
  @moduledoc """
  Records transaction broadcast attempts and their outcomes.

  Status transitions: pending → accepted | rejected.
  On rejection, the `error` field contains the node's error message.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "broadcasts" do
    field :txid, :string
    field :hex, :string
    field :status, :string, default: "pending"
    field :error, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @valid_statuses ~w(pending accepted rejected)

  @doc """
  Builds a changeset for recording a broadcast attempt.

  ## Parameters
    - `broadcast` — existing struct or empty schema
    - `attrs` — map with :txid, :hex, :status (enum), and optional :error

  ## Returns
    An `Ecto.Changeset` validating status is one of pending/accepted/rejected.
  """
  def changeset(broadcast, attrs) do
    broadcast
    |> cast(attrs, [:txid, :hex, :status, :error])
    |> validate_required([:txid, :hex, :status])
    |> validate_inclusion(:status, @valid_statuses)
  end
end
