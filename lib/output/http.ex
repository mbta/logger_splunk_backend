defmodule Logger.Backend.Splunk.Output.Http do
  require Logger

  def transmit(entry, host, token) do
    headers = [{"Authorization", "Splunk #{token}"}, {"Content-Type", "application/json"}]
    opts = [hackney: [pool: :logger_splunk_backend]]
    HTTPoison.post(host, IO.iodata_to_binary(entry), headers, opts)
  end
end
