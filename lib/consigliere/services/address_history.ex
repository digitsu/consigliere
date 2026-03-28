defmodule Consigliere.Services.AddressHistory do
  @moduledoc """
  Queries address transaction history with pagination and filtering.
  """

  alias Consigliere.Repo
  alias Consigliere.Schema.AddressHistory
  import Ecto.Query

  @doc """
  Returns paginated transaction history for an address.

  ## Options
    - `:skip` — offset (default 0)
    - `:take` — limit (default 50)
    - `:token_id` — filter by token ID
    - `:direction` — filter by "in" or "out"
    - `:desc` — sort descending (default true)
    - `:skip_zero_balance` — exclude zero-satoshi entries (default false)
  """
  def list(address, opts \\ []) do
    skip = Keyword.get(opts, :skip, 0)
    take = Keyword.get(opts, :take, 50)
    token_id = Keyword.get(opts, :token_id)
    direction = Keyword.get(opts, :direction)
    desc = Keyword.get(opts, :desc, true)
    skip_zero = Keyword.get(opts, :skip_zero_balance, false)

    query =
      AddressHistory
      |> where([h], h.address == ^address)

    query = if token_id, do: where(query, [h], h.token_id == ^token_id), else: query
    query = if direction, do: where(query, [h], h.direction == ^direction), else: query
    query = if skip_zero, do: where(query, [h], h.satoshis > 0), else: query

    query =
      if desc do
        order_by(query, [h], desc: h.timestamp)
      else
        order_by(query, [h], asc: h.timestamp)
      end

    query
    |> offset(^skip)
    |> limit(^take)
    |> Repo.all()
  end

  @doc """
  Returns the total count of history entries for an address.
  """
  def count(address) do
    AddressHistory
    |> where([h], h.address == ^address)
    |> select([h], count(h.id))
    |> Repo.one()
  end
end
