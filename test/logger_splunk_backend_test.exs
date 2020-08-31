defmodule Logger.Backend.Splunk.Test do
  use ExUnit.Case, async: false
  require Logger

  @backend {Logger.Backend.Splunk, :test}
  Logger.add_backend @backend

  setup do
    Application.ensure_all_started(:bypass)
    bypass = Bypass.open()

    config([
      host: "http://127.0.0.1:#{bypass.port}/",
      format: "[$level] $message",
      token: "<<splunk-token>>",
      max_buffer: 0
    ])
    {:ok, %{bypass: bypass}}
  end

  test "default logger level is `:debug`" do
    assert Logger.level() == :debug
  end

  test "does log when level is above or equal minimum Logger level", opts do
    agent = connect_log_agent(opts.bypass)
    config(level: :info)
    Logger.debug("do not log me")
    Logger.warn("you will log me")
    data = Jason.decode!(read_log(agent))
    assert data["event"] == "[warn] you will log me"
    assert is_float(data["time"])
    assert data["sourcetype"] == "httpevent"
    assert is_binary(data["host"])
  end

  test "can configure format", opts do
    agent = connect_log_agent(opts.bypass)
    config format: "$message ($level)\n"

    Logger.info("I am formatted")
    assert read_log(agent) =~ "I am formatted (info)"
  end

  test "can configure metadata", opts do
    agent = connect_log_agent(opts.bypass)
    config format: "$metadata$message\n", metadata: [:user_id, :auth]

    Logger.info("hello")
    assert read_log(agent) =~ "hello"

    Logger.metadata(auth: true)
    Logger.metadata(user_id: 11)
    Logger.metadata(user_id: 13)

    Logger.info("hello")
    assert read_log(agent) =~ "user_id=13 auth=true hello"
  end

  test "can handle multi-line messages", opts do
    agent = connect_log_agent(opts.bypass)
    config format: "$metadata$message\n", metadata: [:user_id, :auth]
    Logger.metadata(auth: true)
    Logger.info("hello\n world")
    assert read_log(agent) =~ "auth=true hello\\n world"
  end

  test "makes sure messages end with a newline", opts do
    agent = connect_log_agent(opts.bypass)
    Logger.info("hello")
    assert read_log(agent) =~ "[info] hello"
    Logger.info("hello\n")
    assert read_log(agent) =~ "[info] hello\\n"
  end

  @tag :skip
  test "buffers messages", opts do
    agent = connect_log_agent(opts.bypass)
    config(max_buffer: 2)
    Logger.info("hello")
    assert read_log(agent) == ""
    Logger.info("again")
    assert read_log(agent) =~ "hello"
    assert read_log(agent) =~ "again"
    Logger.info("1")
    refute read_log(agent)
    Logger.info("2")
    assert read_log(agent) =~ "1"
    assert read_log(agent) =~ "2"
  end

  @tag :skip
  test "handles flush/0", opts do
    agent = connect_log_agent(opts.bypass)
    config(max_buffer: 2)
    Logger.info("hello")
    assert read_log(agent) == ""
    Logger.flush()
    assert read_log(agent) =~ "hello"
  end

  defp config(opts) do
    Logger.configure_backend(@backend, opts)
  end

  def connect_log_agent(bypass) do
    {:ok, pid} = Agent.start_link(fn -> [] end)
    Bypass.expect(bypass, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      Agent.update(pid, fn value -> [value, body] end)
      Plug.Conn.send_resp(conn, 200, "")
    end)

    pid
  end

  def read_log(pid) do
    Logger.flush()
    Agent.get(pid, fn x -> x |> IO.iodata_to_binary() end)
  end
end
