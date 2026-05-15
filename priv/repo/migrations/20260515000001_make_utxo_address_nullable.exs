defmodule Athanor.Repo.Migrations.MakeUtxoAddressNullable do
  @moduledoc """
  STAS3 token outputs do not match the P2PKH template recognised by
  `BSV.Script.Address.from_script/2`; the owner PKH sits in a different
  script position (spec v0.1 §5.2.2). The indexer now derives a base58
  address from that owner PKH for STAS3 outputs, but for any future
  template variant where extraction isn't safe, the column must permit
  NULL so the UTXO row can still record satoshis + script.
  """

  use Ecto.Migration

  def change do
    alter table(:utxos) do
      modify :address, :text, null: true, from: {:text, null: false}
    end
  end
end
