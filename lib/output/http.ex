defmodule Logger.Backend.Splunk.Output.Http do
  def transmit(entry, host, port, token) do
    msg = Poison.encode!(%{sourcetype: "httpevent", event: entry})

    IO.puts "in transmit *****************"
    {:ok, _response} = HTTPoison.post(host, msg,
      [{"Authorization", "Splunk #{token}"},
       {"Content-Type", "application/json"}],
      [hackney: [pool: :logger_splunk_backend]])
  end
end
