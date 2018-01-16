defmodule Logger.Backend.Splunk.Output.Ssl do
  def transmit(host, port, message, token) do
    msg = "{\"sourcetype\": \"httpevent\", \"event\": #{message}}"
    HTTPoison.start
    HTTPoison.request(:post, "127.0.0.1:8080", "test", [{"Authorization", "Splunk token"}])
  end

  defp tcp_send({:error, error}, _message) do
    IO.puts("ERROR while sending via SSL to log entries: #{inspect error}")
  end

  defp tcp_send({:ok, socket}, message) do
    :ssl.send(socket, message)
    :ssl.close(socket)
  end
end
