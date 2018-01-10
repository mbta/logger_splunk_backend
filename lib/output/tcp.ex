defmodule Logger.Backend.Splunk.Output.Tcp do
  def transmit(host, port, message) do
    :gen_tcp.connect(host, port, [:binary, active: false])
    |> tcp_send(message)
  end

  defp tcp_send({:error, error}, _message) do
    IO.puts("ERROR while sending via TCP to log entries: #{inspect error}")
  end

  defp tcp_send({:ok, socket}, message) do
    :gen_tcp.send(socket, message)
    :gen_tcp.close(socket)
  end
end
