defmodule Athanor.Repo.Migrations.CreateUtxos do
  @moduledoc """
  Creates the utxos table for tracking unspent/spent transaction outputs.
  Composite indexes on (address, is_spent), (token_id, is_spent), and unique (txid, vout).
  """

  use Ecto.Migration

  def change do
    create table(:utxos, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :txid, :binary, null: false
      add :vout, :integer, null: false
      add :address, :text, null: false
      add :satoshis, :bigint, null: false
      add :script_hex, :text, null: false
      add :token_id, :text
      add :token_type, :text
      add :is_spent, :boolean, default: false, null: false
      add :spent_txid, :binary
      add :block_height, :integer

      timestamps(type: :utc_datetime)
    end

    create unique_index(:utxos, [:txid, :vout], name: :utxos_txid_vout_index)
    create index(:utxos, [:address, :is_spent])
    create index(:utxos, [:token_id, :is_spent])
  end
end
