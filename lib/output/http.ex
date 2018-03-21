defmodule Logger.Backend.Splunk.Output.Http do
  require Logger

  def transmit(entry, host, token) do
    msg = Poison.encode!(%{sourcetype: "httpevent", event: entry})

    headers = [{"Authorization", "Splunk #{token}"}, {"Content-Type", "application/json"}]
    opts = [hackney: [pool: :logger_splunk_backend]]
    case HTTPoison.post(host, msg, headers, opts) do
      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.warn("Splunk Logger HTTP POST request failed: #{inspect reason}")
      {:ok, _response} ->
        nil
    end
  end
end
