defmodule Consigliere.Schema.WatchingTokenTest do
  use Consigliere.DataCase, async: true

  alias Consigliere.Schema.WatchingToken

  describe "changeset/2" do
    test "valid with required token_id" do
      changeset = WatchingToken.changeset(%WatchingToken{}, %{token_id: "tok123"})
      assert changeset.valid?
    end

    test "valid with token_id and symbol" do
      changeset = WatchingToken.changeset(%WatchingToken{}, %{token_id: "tok123", symbol: "TST"})
      assert changeset.valid?
    end

    test "invalid without token_id" do
      changeset = WatchingToken.changeset(%WatchingToken{}, %{symbol: "TST"})
      refute changeset.valid?
      assert %{token_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "enforces unique token_id constraint" do
      {:ok, _} = Repo.insert(WatchingToken.changeset(%WatchingToken{}, %{token_id: "dup_tok"}))
      {:error, changeset} = Repo.insert(WatchingToken.changeset(%WatchingToken{}, %{token_id: "dup_tok"}))
      assert %{token_id: ["has already been taken"]} = errors_on(changeset)
    end
  end
end
