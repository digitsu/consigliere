defmodule Athanor.Repo.Migrations.AddStas3Metadata do
  @moduledoc """
  Adds STAS 3.0 specific metadata columns introduced for spec v0.1 hardening:

    * `utxos.stas3_op` — operation class derived from the spendType byte of
      the spending input's unlocking script (see spec §8.2 / §9.6 and
      `Athanor.Tokens.SpendType`). Nullable; populated only for STAS 3.0
      outputs whose authoritative spend has been observed.

    * `watching_tokens.canonical_post_op_return` — the byte sequence that
      follows `OP_RETURN` in the STAS 3.0 issuance (spec §4). The first
      observed value is recorded here; subsequent outputs of the same
      protoID are validated against it (see
      `Athanor.Indexer.TransactionProcessor`). Nullable until first
      observation.

    * `watching_tokens.freeze_auth` / `watching_tokens.confiscate_auth` —
      20-byte HASH160 service-field authorities extracted from the post
      OP_RETURN payload when the FREEZABLE / CONFISCATABLE flag bit is
      set (spec §5.2.3). Nullable; populated when the issuance is first
      observed by the indexer.
  """

  use Ecto.Migration

  def change do
    alter table(:utxos) do
      add :stas3_op, :string
    end

    alter table(:watching_tokens) do
      add :canonical_post_op_return, :binary
      add :freeze_auth, :binary
      add :confiscate_auth, :binary
    end
  end
end
