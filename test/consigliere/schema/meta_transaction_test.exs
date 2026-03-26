defmodule Consigliere.Schema.MetaTransactionTest do
  use Consigliere.DataCase, async: true

  alias Consigliere.Schema.MetaTransaction
  import Consigliere.Fixtures

  describe "changeset/2" do
    test "valid with required fields" do
      attrs = meta_transaction_attrs()
      changeset = MetaTransaction.changeset(%MetaTransaction{}, attrs)
      assert changeset.valid?
    end

    test "invalid without txid" do
      attrs = meta_transaction_attrs() |> Map.delete(:txid)
      changeset = MetaTransaction.changeset(%MetaTransaction{}, attrs)
      refute changeset.valid?
      assert %{txid: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without hex" do
      attrs = meta_transaction_attrs() |> Map.delete(:hex)
      changeset = MetaTransaction.changeset(%MetaTransaction{}, attrs)
      refute changeset.valid?
      assert %{hex: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without timestamp" do
      attrs = meta_transaction_attrs() |> Map.delete(:timestamp)
      changeset = MetaTransaction.changeset(%MetaTransaction{}, attrs)
      refute changeset.valid?
      assert %{timestamp: ["can't be blank"]} = errors_on(changeset)
    end

    test "inserts and reads back successfully" do
      tx = meta_transaction_fixture()
      assert tx.id != nil
      assert tx.is_confirmed == false
    end
  end
end
