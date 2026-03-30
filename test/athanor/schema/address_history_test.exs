defmodule Athanor.Schema.AddressHistoryTest do
  use Athanor.DataCase, async: true

  alias Athanor.Schema.AddressHistory
  import Athanor.Fixtures

  describe "changeset/2" do
    test "valid with required fields" do
      attrs = address_history_attrs()
      changeset = AddressHistory.changeset(%AddressHistory{}, attrs)
      assert changeset.valid?
    end

    test "valid with direction in" do
      attrs = address_history_attrs(%{direction: "in"})
      changeset = AddressHistory.changeset(%AddressHistory{}, attrs)
      assert changeset.valid?
    end

    test "valid with direction out" do
      attrs = address_history_attrs(%{direction: "out"})
      changeset = AddressHistory.changeset(%AddressHistory{}, attrs)
      assert changeset.valid?
    end

    test "invalid with bad direction" do
      attrs = address_history_attrs(%{direction: "sideways"})
      changeset = AddressHistory.changeset(%AddressHistory{}, attrs)
      refute changeset.valid?
      assert %{direction: _} = errors_on(changeset)
    end

    test "invalid without address" do
      attrs = address_history_attrs() |> Map.delete(:address)
      changeset = AddressHistory.changeset(%AddressHistory{}, attrs)
      refute changeset.valid?
    end

    test "inserts successfully" do
      history = address_history_fixture()
      assert history.id != nil
      assert history.direction == "in"
    end
  end
end
