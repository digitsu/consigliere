defmodule Consigliere.Services.Balance do
  @moduledoc """
  Computes address balances by summing unspent UTXOs, both BSV and tokens.

  TODO: Implement token-aware balance queries in Phase 3.
  """

  alias Consigliere.Repo
  alias Consigliere.Schema.Utxo
  import Ecto.Query

  @doc """
  Returns the BSV balance (in satoshis) for an address.

  ## Parameters
    - `address` — BSV address string

  ## Returns
    Integer satoshi balance from unspent non-token UTXOs.
  """
  def get_balance(address) do
    Utxo
    |> where([u], u.address == ^address and u.is_spent == false and is_nil(u.token_id))
    |> select([u], sum(u.satoshis))
    |> Repo.one()
    |> Kernel.||(0)
  end
end
