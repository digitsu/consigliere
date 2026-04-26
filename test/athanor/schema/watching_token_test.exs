defmodule Athanor.Schema.WatchingTokenTest do
  use Athanor.DataCase, async: true

  alias Athanor.Schema.WatchingToken

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

      {:error, changeset} =
        Repo.insert(WatchingToken.changeset(%WatchingToken{}, %{token_id: "dup_tok"}))

      assert %{token_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "accepts canonical_post_op_return + 20-byte freeze_auth and confiscate_auth" do
      attrs = %{
        token_id: "proto_aabb",
        canonical_post_op_return: <<0x14, 0xAA>>,
        freeze_auth: :binary.copy(<<0x11>>, 20),
        confiscate_auth: :binary.copy(<<0x22>>, 20)
      }

      changeset = WatchingToken.changeset(%WatchingToken{}, attrs)
      assert changeset.valid?
    end

    test "rejects non-20-byte authority fields" do
      changeset =
        WatchingToken.changeset(%WatchingToken{}, %{
          token_id: "proto_bad",
          freeze_auth: <<0x11, 0x22>>
        })

      refute changeset.valid?
      assert %{freeze_auth: ["must be a 20-byte HASH160"]} = errors_on(changeset)
    end
  end
end
