defmodule Logger.Backend.Splunk.Output.Ssl do
  def transmit(host, port, message) do
    :ssl.connect(host, port, [:binary, active: false])
    |> tcp_send(message)
  end

  defp tcp_send({:error, error}, _message) do
    IO.puts("ERROR while sending via SSL to log entries: #{inspect error}")
  end

  defp tcp_send({:ok, socket}, message) do
    :ssl.send(socket, message)
    :ssl.close(socket)
  end
end
