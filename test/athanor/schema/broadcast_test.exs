defmodule Athanor.Schema.BroadcastTest do
  use Athanor.DataCase, async: true

  alias Athanor.Schema.Broadcast
  import Athanor.Fixtures

  describe "changeset/2" do
    test "valid with required fields" do
      attrs = broadcast_attrs()
      changeset = Broadcast.changeset(%Broadcast{}, attrs)
      assert changeset.valid?
    end

    test "valid with all statuses" do
      for status <- ~w(pending accepted rejected) do
        attrs = broadcast_attrs(%{status: status})
        changeset = Broadcast.changeset(%Broadcast{}, attrs)
        assert changeset.valid?, "expected #{status} to be valid"
      end
    end

    test "invalid with bad status" do
      attrs = broadcast_attrs(%{status: "unknown"})
      changeset = Broadcast.changeset(%Broadcast{}, attrs)
      refute changeset.valid?
      assert %{status: _} = errors_on(changeset)
    end

    test "invalid without txid" do
      attrs = broadcast_attrs() |> Map.delete(:txid)
      changeset = Broadcast.changeset(%Broadcast{}, attrs)
      refute changeset.valid?
    end

    test "inserts successfully" do
      broadcast = broadcast_fixture()
      assert broadcast.id != nil
      assert broadcast.status == "pending"
    end
  end
end
