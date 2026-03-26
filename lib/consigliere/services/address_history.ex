defmodule Consigliere.Services.AddressHistory do
  @moduledoc """
  Queries address transaction history with pagination and filtering.

  TODO: Implement full query logic in Phase 3.
  """

  alias Consigliere.Repo
  alias Consigliere.Schema.AddressHistory
  import Ecto.Query

  @doc """
  Returns paginated transaction history for an address.

  ## Parameters
    - `address` — BSV address string
    - `opts` — keyword list with :skip, :take, :token_id, :direction

  ## Returns
    List of `AddressHistory` structs ordered by timestamp descending.
  """
  def list(address, opts \\ []) do
    skip = Keyword.get(opts, :skip, 0)
    take = Keyword.get(opts, :take, 50)

    AddressHistory
    |> where([h], h.address == ^address)
    |> order_by([h], desc: h.timestamp)
    |> offset(^skip)
    |> limit(^take)
    |> Repo.all()
  end
end
