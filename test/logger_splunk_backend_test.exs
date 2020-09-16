defmodule Logger.Backend.Splunk.Test do
  use ExUnit.Case, async: false
  alias Logger.Backend.Splunk.FakeIO
  require Logger

  @backend {Logger.Backend.Splunk, __MODULE__}

  setup do
    Application.ensure_all_started(:bypass)
    bypass = Bypass.open()

    case Logger.add_backend(@backend) do
      {:ok, _} ->
        :ok

      {:error, :already_present} ->
        Logger.remove_backend(@backend)
        {:ok, _} = Logger.add_backend(@backend)
        :ok
    end

    {:ok, io} = FakeIO.start_link()

    config(
      host: "http://127.0.0.1:#{bypass.port}/",
      format: "$metadata[$level] $message",
      token: "<<splunk-token>>",
      max_buffer: 0,
      error_device: io
    )

    on_exit(fn ->
      Logger.remove_backend(@backend)
    end)

    {:ok, %{bypass: bypass, io: io}}
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
    config(format: "$message ($level)\n")

    Logger.info("I am formatted")
    assert read_log(agent) =~ "I am formatted (info)"
  end

  test "can configure metadata", opts do
    agent = connect_log_agent(opts.bypass)
    config(format: "$metadata$message\n", metadata: [:user_id, :auth])

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
    config(format: "$metadata$message\n", metadata: [:user_id, :auth])
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

  test "buffers messages", opts do
    agent = connect_log_agent(opts.bypass)
    config(max_buffer: 1)
    # sends immediately
    Logger.info("hello")
    # buffers
    Logger.info("again")
    refute read_log(agent, false) =~ "again"
    # reads the record on flush
    assert read_log(agent) =~ "again"
  end

  test "can handle lots of messages without losing any", opts do
    Logger.flush()
    agent = connect_log_agent(opts.bypass, 10)
    config(max_buffer: 2)

    messages =
      for index <- 0..100 do
        message = "index-#{index}-"
        Logger.info(message)
        message
      end

    log = read_log(agent)

    for message <- messages do
      assert log =~ message
    end

    count = count_log(agent)
    # 1 message first + 50 for the other 99 while buffering 2 messages
    assert count == 51
  end

  test "handles flush/0", opts do
    agent = connect_log_agent(opts.bypass)
    config(max_buffer: 2)
    Logger.info("hello")
    assert read_log(agent, false) == ""
    Logger.flush()
    assert read_log(agent) =~ "hello"
  end

  test "does not crash when Splunk returns a non-200 error code", opts do
    Bypass.expect(opts.bypass, fn conn ->
      {:ok, _body, conn} = Plug.Conn.read_body(conn)
      Plug.Conn.send_resp(conn, 404, "404 body")
    end)

    :ok = Logger.info("should not crash on invalid status")
    :ok = Logger.flush()

    error_output = FakeIO.get(opts.io)
    assert error_output =~ "ERROR unexpected status code when logging to Splunk: 404"
    assert error_output =~ "should not crash on invalid status"
    assert error_output =~ "404 body"
  end

  test "does not crash when Splunk is down", opts do
    Bypass.down(opts.bypass)
    :ok = Logger.info("should not crash")
    :ok = Logger.flush()
    Bypass.up(opts.bypass)
    :ok = Logger.info("should not crash")
    :ok = Logger.info("should not crash")
    Bypass.down(opts.bypass)
    :ok = Logger.info("should not crash")
    :ok = Logger.flush()

    error_output = FakeIO.get(opts.io)
    assert error_output =~ "ERROR unable to connect to Splunk: :econnrefused"
    assert error_output =~ "should not crash"
  end

  defp config(opts) do
    Logger.configure_backend(@backend, opts)
  end

  defp connect_log_agent(bypass, delay \\ 0) do
    {:ok, pid} = Agent.start_link(fn -> [] end)

    Bypass.expect(bypass, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      Agent.update(pid, fn value -> [value, body] end)
      Process.sleep(delay)
      Plug.Conn.send_resp(conn, 200, ~S[{"text": "Success", "code": 0}])
    end)

    pid
  end

  defp read_log(pid, flush? \\ true) do
    if flush?, do: Logger.flush()
    Agent.get(pid, &IO.iodata_to_binary/1)
  end

  defp count_log(pid) do
    Agent.get(pid, &count_lines/1)
  end

  defp count_lines(lines, acc \\ 0)

  defp count_lines([rest, _line], acc) do
    count_lines(rest, acc + 1)
  end

  defp count_lines([], acc) do
    acc
  end
end
