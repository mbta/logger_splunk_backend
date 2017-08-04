defmodule Logger.Backend.Logentries.Output.SslKeepOpen do
  def transmit(host, port, message) do
    Logger.Backend.Logentries.Output.SslKeepOpen.Server.transmit(host, port, message)
  end
end

defmodule Logger.Backend.Logentries.Output.SslKeepOpen.Server do
  @moduledoc """

  A GenServer which maintains connections to the Logentries server.

  ## Usage

  Configure the Logentries backend to use the SslKeepOpen backend:

      config :logger, :logentries,
        connector: Logger.Backend.Logentries.Output.SslKeepOpen,
        host: 'data.logentries.com',
        port: 443,
        token: "${LOGENTRIES_TOKEN}",

  And make sure this server is supervised:

      # In your application
      worker(Logger.Backend.Logentries.Output.SslKeepOpen.Server, [])

  """
  use GenServer

  defstruct [
    connections: %{}
  ]

  def child_spec(_args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  def start_link do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def transmit(host, port, message) do
    GenServer.cast(__MODULE__, {:transmit, host, port, message})
  end

  @impl true
  def init(nil) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_cast({:transmit, host, port, message}, state) do
    socket = state
    |> ensure_connection(host, port)
    |> send_message(message)

    new_state = put_in state.connections[{host, port}], socket

    {:noreply, new_state}
  end

  defp ensure_connection(%{connections: connections}, host, port) do
    case Map.get(connections, {host, port}) do
      nil ->
        new_socket(host, port)
      {:error, _error} ->
        new_socket(host, port)
      socket ->
        socket
    end
  end

  defp send_message({:ok, socket}, message) do
    case :ssl.send(socket, message) do
      :ok ->
        {:ok, socket}
      {:error, error} ->
        IO.puts("ERROR sending message: #{inspect error}")
        {:error, error}
    end
  end
  defp send_message({:error, error}, _) do
    IO.puts("ERROR connecting: #{inspect error}")
    {:error, error}
  end

  defp new_socket(host, port) do
    :ssl.connect(host, port, [:binary, active: false])
  end
end
