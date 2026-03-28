defmodule Consigliere.Indexer.B2gResolver do
  @moduledoc """
  Back-to-Genesis resolver — walks the input chain of a STAS token output
  back to the genesis issuance transaction to verify provenance.

  Strategy:
  1. Look up the UTXO locally
  2. Walk backwards through inputs, checking each for STAS token type
  3. For each step, try local DB first, then RPC, then WoC fallback
  4. Genesis is reached when a non-STAS input is found (the issuance tx)
  """

  require Logger

  alias Consigliere.Repo
  alias Consigliere.Schema.MetaTransaction
  alias Consigliere.Blockchain.RpcClient
  alias Consigliere.Infra.WhatsOnChain
  alias Consigliere.Tokens.Classifier

  @max_depth 1000

  @doc """
  Resolves the provenance chain for a given STAS UTXO.

  ## Parameters
    - `txid` — transaction ID (binary or hex string)
    - `vout` — output index

  ## Returns
    `{:ok, chain}` where chain is a list of `{txid_hex, vout}` from tip to genesis,
    or `{:error, reason}`
  """
  def resolve(txid, vout) do
    txid_hex = normalize_txid(txid)
    walk_chain(txid_hex, vout, [], 0)
  end

  ## ── Private ──

  defp walk_chain(_txid_hex, _vout, _chain, depth) when depth >= @max_depth do
    {:error, :max_depth_exceeded}
  end

  defp walk_chain(txid_hex, vout, chain, depth) do
    chain = [{txid_hex, vout} | chain]

    case fetch_tx(txid_hex) do
      {:ok, tx} ->
        # Check if this output is a STAS token
        outputs = tx.outputs
        output = Enum.at(outputs, vout)

        if output do
          script_binary = BSV.Script.to_binary(output.locking_script)
          script_type = Classifier.classify(script_binary)

          if script_type in [:stas, :stas_btg, :dstas] do
            # Walk back through the corresponding input
            # STAS tokens typically spend input at same index or index 0
            input_idx = min(vout, length(tx.inputs) - 1)
            input = Enum.at(tx.inputs, input_idx)

            if input do
              prev_txid = Base.encode16(input.source_txid, case: :lower)
              prev_vout = input.source_tx_out_index
              walk_chain(prev_txid, prev_vout, chain, depth + 1)
            else
              # No input — this IS genesis
              {:ok, Enum.reverse(chain)}
            end
          else
            # Non-STAS output — this is genesis (issuance tx)
            {:ok, Enum.reverse(chain)}
          end
        else
          {:error, :output_not_found}
        end

      {:error, reason} ->
        Logger.warning("B2G resolve failed at #{txid_hex}:#{vout} depth=#{depth}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_tx(txid_hex) do
    # Try local DB first
    case fetch_local(txid_hex) do
      {:ok, tx} -> {:ok, tx}
      {:error, _} -> fetch_remote(txid_hex)
    end
  end

  defp fetch_local(txid_hex) do
    case Base.decode16(txid_hex, case: :mixed) do
      {:ok, txid_binary} ->
        case Repo.get_by(MetaTransaction, txid: txid_binary) do
          %MetaTransaction{hex: hex} when hex != nil ->
            case BSV.Transaction.from_hex(hex) do
              {:ok, tx, _rest} -> {:ok, tx}
              {:error, reason} -> {:error, reason}
            end

          _ ->
            {:error, :not_found}
        end

      :error ->
        {:error, :invalid_txid}
    end
  end

  defp fetch_remote(txid_hex) do
    # Try RPC first
    case RpcClient.get_raw_transaction(txid_hex, false) do
      {:ok, raw_hex} ->
        parse_hex(raw_hex)

      {:error, _} ->
        # Fallback to WhatsOnChain
        case WhatsOnChain.get_raw_tx(txid_hex) do
          {:ok, raw_hex} -> parse_hex(raw_hex)
          {:error, _} = err -> err
        end
    end
  end

  defp parse_hex(hex) do
    case BSV.Transaction.from_hex(hex) do
      {:ok, tx, _rest} -> {:ok, tx}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_txid(txid) when is_binary(txid) and byte_size(txid) == 32 do
    Base.encode16(txid, case: :lower)
  end

  defp normalize_txid(txid) when is_binary(txid), do: String.downcase(txid)
end
