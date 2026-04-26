defmodule Athanor.Indexer.TransactionProcessor do
  @moduledoc """
  Core indexing pipeline: receives filtered transactions, parses outputs,
  classifies them (P2PKH/STAS/STAS3), updates the UTXO set in Postgres,
  records address history, and publishes events via PubSub.

  Pipeline: filter → parse → classify → store → notify
  """

  use GenServer
  require Logger

  alias Athanor.Repo
  alias Athanor.Schema.{MetaTransaction, AddressHistory, WatchingToken}
  alias Athanor.Indexer.UtxoManager
  alias Athanor.Tokens.{Classifier, SpendType, Stas3Meta}
  alias BSV.Tokens.Script.Reader, as: ScriptReader
  alias BSV.Transaction

  ## ── Client API ──

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Synchronously process a transaction (for block processing).
  """
  def process_tx(tx, matched_addresses, matched_tokens) do
    GenServer.call(__MODULE__, {:process_tx, tx, matched_addresses, matched_tokens}, 30_000)
  end

  ## ── Server Callbacks ──

  @impl true
  def init(_opts) do
    {:ok, %{processed_count: 0}}
  end

  @impl true
  def handle_cast({:index_tx, tx, matched_addresses, matched_tokens}, state) do
    do_index_tx(tx, matched_addresses, matched_tokens, nil)
    {:noreply, %{state | processed_count: state.processed_count + 1}}
  end

  @impl true
  def handle_call({:process_tx, tx, matched_addresses, matched_tokens}, _from, state) do
    result = do_index_tx(tx, matched_addresses, matched_tokens, nil)
    {:reply, result, %{state | processed_count: state.processed_count + 1}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## ── Private ──

  defp do_index_tx(tx, matched_addresses, matched_tokens, block_height) do
    txid_binary = Transaction.txid_binary(tx)
    txid_hex = Transaction.tx_id_hex(tx)
    tx_hex = Transaction.to_hex(tx)

    # Classify all outputs
    classified = Classifier.classify_outputs(tx)

    # Collect all involved addresses and token IDs
    all_addresses = extract_all_addresses(tx)
    all_token_ids = extract_all_token_ids(classified)

    # 1. Store MetaTransaction
    meta_attrs = %{
      txid: txid_binary,
      hex: tx_hex,
      block_height: block_height,
      is_confirmed: block_height != nil,
      timestamp: System.os_time(:second),
      addresses: all_addresses,
      token_ids: all_token_ids,
      metadata: %{}
    }

    _meta_result =
      case Repo.get_by(MetaTransaction, txid: txid_binary) do
        nil ->
          %MetaTransaction{}
          |> MetaTransaction.changeset(meta_attrs)
          |> Repo.insert()

        existing ->
          existing
          |> MetaTransaction.changeset(meta_attrs)
          |> Repo.update()
      end

    # 2. Process inputs — mark UTXOs as spent. STAS 3.0 spec v0.1 §8.2 / §9.6:
    # the unlocking script encodes a `spendType` byte that classifies the
    # operation (transfer / freeze_unfreeze / confiscation / swap_cancel).
    # Record this on the spent UTXO so downstream queries can recover the
    # operation class. Non-STAS-3.0 inputs are skipped — the parser only
    # runs against confirmed STAS 3.0 unlocks.
    spend_op = stas3_spend_op(tx)

    Enum.each(tx.inputs, fn input ->
      unless Transaction.is_coinbase?(tx) do
        source_txid = input.source_txid
        UtxoManager.spend_utxo(source_txid, input.source_tx_out_index, txid_binary)

        if spend_op do
          UtxoManager.set_stas3_op(source_txid, input.source_tx_out_index, spend_op)
        end
      end
    end)

    # 3. Process outputs — create new UTXOs. For STAS 3.0 outputs whose
    # protoID matches a watched issuance, validate the post-OP_RETURN
    # payload (spec §4) byte-identity invariant and seed the canonical
    # bytes / service-field authorities (spec §5.2.3) on first sight.
    Enum.each(classified, fn {vout, script_type, token_id} ->
      output = Enum.at(tx.outputs, vout)
      script_binary = BSV.Script.to_binary(output.locking_script)

      address =
        case BSV.Script.Address.from_script(output.locking_script) do
          {:ok, addr} -> addr
          :error -> nil
        end

      token_type =
        case script_type do
          :stas -> "stas"
          :stas_btg -> "stas"
          :stas3 -> "stas3"
          _ -> nil
        end

      tampered? =
        script_type == :stas3 and
          stas3_post_op_return_tampered?(token_id, script_binary)

      cond do
        tampered? ->
          Logger.warning(
            "STAS3 post-OP_RETURN mismatch for protoID=#{token_id} tx=#{txid_hex} vout=#{vout}; skipping output indexing per spec §4 byte-identity invariant"
          )

        true ->
          utxo_attrs = %{
            txid: txid_binary,
            vout: vout,
            address: address,
            satoshis: output.satoshis,
            script_hex: Base.encode16(script_binary, case: :lower),
            token_id: token_id,
            token_type: token_type,
            is_spent: false,
            block_height: block_height
          }

          UtxoManager.create_utxo(utxo_attrs)

          if script_type == :stas3 do
            seed_watching_token_metadata(token_id, script_binary)
          end
      end
    end)

    # 4. Record address history for matched addresses
    Enum.each(matched_addresses, fn address ->
      # Determine direction: in if address appears in outputs, out if in inputs
      direction = determine_direction(tx, address)
      satoshis = calculate_address_amount(tx, address, classified)

      history_attrs = %{
        address: address,
        txid: txid_hex,
        direction: direction,
        satoshis: satoshis,
        block_height: block_height,
        timestamp: System.os_time(:second)
      }

      %AddressHistory{}
      |> AddressHistory.changeset(history_attrs)
      |> Repo.insert()
    end)

    # 5. Publish events via PubSub
    Enum.each(matched_addresses, fn address ->
      Phoenix.PubSub.broadcast(
        Athanor.PubSub,
        "tx:#{address}",
        {:tx_found, %{txid: txid_hex, address: address}}
      )

      Phoenix.PubSub.broadcast(
        Athanor.PubSub,
        "balance:#{address}",
        {:balance_changed, %{address: address}}
      )
    end)

    Logger.info(
      "Indexed tx #{txid_hex} (#{length(matched_addresses)} addrs, #{length(matched_tokens)} tokens)"
    )

    {:ok, txid_hex}
  end

  defp extract_all_addresses(tx) do
    tx.outputs
    |> Enum.map(fn output ->
      case BSV.Script.Address.from_script(output.locking_script) do
        {:ok, addr} -> addr
        :error -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp extract_all_token_ids(classified) do
    classified
    |> Enum.map(fn {_vout, _type, token_id} -> token_id end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp determine_direction(tx, address) do
    output_addrs =
      tx.outputs
      |> Enum.map(fn o ->
        case BSV.Script.Address.from_script(o.locking_script) do
          {:ok, a} -> a
          :error -> nil
        end
      end)

    if address in output_addrs, do: "in", else: "out"
  end

  defp calculate_address_amount(tx, address, _classified) do
    tx.outputs
    |> Enum.filter(fn output ->
      case BSV.Script.Address.from_script(output.locking_script) do
        {:ok, ^address} -> true
        _ -> false
      end
    end)
    |> Enum.map(& &1.satoshis)
    |> Enum.sum()
  end

  # Walk the transaction's inputs and return the first observed STAS 3.0
  # spendType class (per spec v0.1 §8.2). Returns the string form expected
  # by `Athanor.Schema.Utxo.stas3_op` or `nil` when no STAS 3.0 unlocking
  # script is found / parses cleanly. Multiple STAS 3.0 inputs in a single
  # tx are required by the spec to share the same spendType, so the first
  # successful parse wins.
  defp stas3_spend_op(tx) do
    if Transaction.is_coinbase?(tx) do
      nil
    else
      Enum.find_value(tx.inputs, fn input ->
        case input.unlocking_script do
          nil ->
            nil

          script ->
            unlocking_bin = BSV.Script.to_binary(script)

            case SpendType.parse(unlocking_bin) do
              {:ok, op} -> SpendType.to_string(op)
              {:error, _} -> nil
            end
        end
      end)
    end
  end

  # Spec v0.1 §4: the post-OP_RETURN region is byte-identical across every
  # spend of a given STAS 3.0 issuance. If we already have a canonical copy
  # for this protoID and the new output's bytes diverge, return true so the
  # caller can warn + skip indexing the malformed output.
  defp stas3_post_op_return_tampered?(nil, _script_binary), do: false

  defp stas3_post_op_return_tampered?(proto_hex, script_binary) do
    with %WatchingToken{canonical_post_op_return: canonical}
         when not is_nil(canonical) <-
           Repo.get_by(WatchingToken, token_id: proto_hex),
         {:ok, observed} <- Stas3Meta.post_op_return(script_binary) do
      observed != canonical
    else
      _ -> false
    end
  end

  # On the first STAS 3.0 output we see for a watched protoID, persist the
  # canonical post-OP_RETURN bytes (spec §4) and any FREEZABLE / CONFISCATABLE
  # service-field authorities (spec §5.2.3). Subsequent outputs do nothing —
  # the byte-identity check above guards against drift.
  defp seed_watching_token_metadata(nil, _script_binary), do: :ok

  defp seed_watching_token_metadata(proto_hex, script_binary) do
    case Repo.get_by(WatchingToken, token_id: proto_hex) do
      nil ->
        :ok

      %WatchingToken{canonical_post_op_return: canonical} = wt
      when is_nil(canonical) ->
        with {:ok, post_op_return} <- Stas3Meta.post_op_return(script_binary),
             %{stas3: %_{} = fields} <- ScriptReader.read_locking_script(script_binary),
             {:ok, %{freeze_auth: f, confiscate_auth: c}} <-
               Stas3Meta.service_authorities(fields) do
          wt
          |> WatchingToken.changeset(%{
            canonical_post_op_return: post_op_return,
            freeze_auth: f,
            confiscate_auth: c
          })
          |> Repo.update()
          |> case do
            {:ok, _} -> :ok
            {:error, cs} -> Logger.warning("STAS3 metadata seed failed: #{inspect(cs.errors)}")
          end
        else
          _ -> :ok
        end

      _ ->
        :ok
    end
  end
end
