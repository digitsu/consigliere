defmodule Consigliere.Repo.Migrations.CreateWatchingTokens do
  @moduledoc """
  Creates the watching_tokens table for admin-managed STAS token watch list.
  """

  use Ecto.Migration

  def change do
    create table(:watching_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :token_id, :text, null: false
      add :symbol, :text

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:watching_tokens, [:token_id])
  end
end
