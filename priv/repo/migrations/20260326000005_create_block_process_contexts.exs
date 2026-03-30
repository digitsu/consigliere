defmodule Athanor.Repo.Migrations.CreateBlockProcessContexts do
  @moduledoc """
  Creates the block_process_contexts table for tracking processed blocks.
  Primary key is the block hash (text), not auto-generated.
  """

  use Ecto.Migration

  def change do
    create table(:block_process_contexts, primary_key: false) do
      add :id, :text, primary_key: true
      add :height, :integer, null: false
      add :processed_at, :utc_datetime, null: false
    end

    create unique_index(:block_process_contexts, [:height])
  end
end
