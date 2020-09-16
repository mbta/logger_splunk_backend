defmodule Logger.Backend.Splunk.FakeIO do
  @moduledoc """
  GenServer which represents a fake IO backend for testing.
  """
  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, [])
  end

  def get(pid) do
    pid
    |> GenServer.call(:get)
    |> IO.iodata_to_binary()
  end

  @impl GenServer
  def init(body) do
    {:ok, body}
  end

  @impl GenServer
  def handle_call(:get, _from, body) do
    {:reply, body, body}
  end

  @impl GenServer
  def handle_info({:io_request, from, ref, {:put_chars, :unicode, chars}}, body) do
    body = [body | chars]
    send(from, {:io_reply, ref, :ok})
    {:noreply, body}
  end
end
