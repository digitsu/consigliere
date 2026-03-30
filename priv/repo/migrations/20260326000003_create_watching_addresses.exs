defmodule Athanor.Repo.Migrations.CreateWatchingAddresses do
  @moduledoc """
  Creates the watching_addresses table for admin-managed address watch list.
  """

  use Ecto.Migration

  def change do
    create table(:watching_addresses, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :address, :text, null: false
      add :name, :text

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:watching_addresses, [:address])
  end
end
