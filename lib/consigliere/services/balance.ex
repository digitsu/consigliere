defmodule Consigliere.Services.Balance do
  @moduledoc """
  Computes address balances by summing unspent UTXOs, both BSV and tokens.
  """

  alias Consigliere.Repo
  alias Consigliere.Schema.Utxo
  import Ecto.Query

  @doc """
  Returns the BSV balance (in satoshis) for an address.
  """
  def get_balance(address) do
    Utxo
    |> where([u], u.address == ^address and u.is_spent == false and is_nil(u.token_id))
    |> select([u], sum(u.satoshis))
    |> Repo.one() || 0
  end

  @doc """
  Returns full balance breakdown: BSV + per-token balances.

  ## Returns
    %{bsv: integer, tokens: [%{token_id: string, satoshis: integer, count: integer}]}
  """
  def get_full_balance(address) do
    bsv = get_balance(address)

    tokens =
      Utxo
      |> where([u], u.address == ^address and u.is_spent == false and not is_nil(u.token_id))
      |> group_by([u], u.token_id)
      |> select([u], %{
        token_id: u.token_id,
        satoshis: sum(u.satoshis),
        count: count(u.id)
      })
      |> Repo.all()

    %{bsv: bsv, tokens: tokens}
  end

  @doc """
  Returns balances for multiple addresses at once.
  """
  def get_balances(addresses) when is_list(addresses) do
    Map.new(addresses, fn addr -> {addr, get_full_balance(addr)} end)
  end

  @doc """
  Returns balances filtered by specific token IDs.
  """
  def get_token_balances(address, token_ids) when is_list(token_ids) do
    Utxo
    |> where([u], u.address == ^address and u.is_spent == false and u.token_id in ^token_ids)
    |> group_by([u], u.token_id)
    |> select([u], %{
      token_id: u.token_id,
      satoshis: sum(u.satoshis),
      count: count(u.id)
    })
    |> Repo.all()
  end
end
