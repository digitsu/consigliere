defmodule Consigliere.Repo.Migrations.CreateBroadcasts do
  @moduledoc """
  Creates the broadcasts table for recording tx broadcast attempts.
  """

  use Ecto.Migration

  def change do
    create table(:broadcasts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :txid, :text, null: false
      add :hex, :text, null: false
      add :status, :text, null: false, default: "pending"
      add :error, :text

      timestamps(type: :utc_datetime, updated_at: false)
    end
  end
end
