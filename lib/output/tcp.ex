defmodule Logger.Backend.Splunk.Output.Tcp do
  def transmit(host, port, message, token) do
    msg = "{\"sourcetype\": \"httpevent\", \"event\": \"#{message}\"}"
    IO.inspect msg
    IO.inspect host
    IO.inspect token
    HTTPoison.start
    HTTPoison.request(:post, host, msg, [{"Authorization", "Splunk #{token}"}])
  end

  defp tcp_send({:error, error}, _message) do
    IO.puts("ERROR while sending via TCP to log entries: #{inspect error}")
  end

  defp tcp_send({:ok, socket}, message) do
    :gen_tcp.send(socket, message)
    :gen_tcp.close(socket)
  end
end
