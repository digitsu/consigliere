defmodule Consigliere.Repo.Migrations.CreateMetaTransactions do
  @moduledoc """
  Creates the meta_transactions table for storing transaction metadata.
  Includes GIN indexes on addresses/token_ids arrays for fast containment queries.
  """

  use Ecto.Migration

  def change do
    create table(:meta_transactions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :txid, :binary, null: false
      add :hex, :text, null: false
      add :block_hash, :binary
      add :block_height, :integer
      add :timestamp, :bigint, null: false
      add :is_confirmed, :boolean, default: false, null: false
      add :addresses, {:array, :text}, default: []
      add :token_ids, {:array, :text}, default: []
      add :metadata, :jsonb, default: "{}"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:meta_transactions, [:txid])
    create index(:meta_transactions, [:addresses], using: "GIN")
    create index(:meta_transactions, [:token_ids], using: "GIN")
    create index(:meta_transactions, [:block_height])
    create index(:meta_transactions, [:is_confirmed])
  end
end
