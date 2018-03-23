defmodule Logger.Backend.Splunk.Output.Http do
  require Logger

  def transmit(entry, host, token) do
    msg = Poison.encode!(%{sourcetype: "httpevent", event: entry})

    headers = [{"Authorization", "Splunk #{token}"}, {"Content-Type", "application/json"}]
    opts = [hackney: [pool: :logger_splunk_backend]]
    HTTPoison.post(host, msg, headers, opts)
  end
end
