defmodule Output.Test do
  @logfile "test_log.log"

  def transmit(message, _host, _token) do
    File.write!(@logfile, message)
  end

  def read() do
    if exists() do
      File.read!(@logfile)
    end
  end

  def exists() do
    File.exists?(@logfile)
  end

  def destroy() do
    if exists() do
      File.rm!(@logfile)
    end
  end
end

defmodule Logger.Backend.Splunk.Test do
  use ExUnit.Case, async: false
  require Logger

  @backend {Logger.Backend.Splunk, :test}
  Logger.add_backend @backend

  setup do
    config([
      connector: Output.Test,
      host: 'splunk.url',
      format: "[$level] $message",
      token: "<<splunk-token>>",
      max_buffer: 0
    ])
    on_exit fn ->
      connector().destroy()
    end
    :ok
  end

  test "default logger level is `:debug`" do
    assert Logger.level() == :debug
  end

  test "does not log when level is under minimum Logger level" do
    config(level: :info)
    Logger.debug("do not log me")
    refute connector().exists()
  end

  test "does log when level is above or equal minimum Logger level" do
    refute connector().exists()
    config(level: :info)
    Logger.warn("you will log me")
    assert connector().exists()
    data = Jason.decode!(read_log())
    assert data["event"] == "[warn] you will log me"
    assert is_float(data["time"])
    assert data["sourcetype"] == "httpevent"
  end

  test "can configure format" do
    config format: "$message ($level)\n"

    Logger.info("I am formatted")
    assert read_log() =~ "I am formatted (info)"
  end

  test "can configure metadata" do
    config format: "$metadata$message\n", metadata: [:user_id, :auth]

    Logger.info("hello")
    assert read_log() =~ "hello"

    Logger.metadata(auth: true)
    Logger.metadata(user_id: 11)
    Logger.metadata(user_id: 13)

    Logger.info("hello")
    assert read_log() =~ "user_id=13 auth=true hello"
  end

  test "can handle multi-line messages" do
    config format: "$metadata$message\n", metadata: [:user_id, :auth]
    Logger.metadata(auth: true)
    Logger.info("hello\n world")
    assert read_log() =~ "auth=true hello\\n world"
  end

  test "makes sure messages end with a newline" do
    Logger.info("hello")
    assert read_log() =~ "[info] hello"
    Logger.info("hello\n")
    assert read_log() =~ "[info] hello\\n"
  end

  test "buffers messages" do
    config(max_buffer: 2)
    Logger.info("hello")
    refute read_log()
    Logger.info("again")
    assert read_log() =~ "hello"
    assert read_log() =~ "again"
    connector().destroy()
    Logger.info("1")
    refute read_log()
    Logger.info("2")
    assert read_log() =~ "1"
    assert read_log() =~ "2"
  end

  test "handles flush/0" do
    config(max_buffer: 2)
    Logger.info("hello")
    refute read_log()
    Logger.flush()
    assert read_log() =~ "hello"
  end

  defp config(opts) do
    Logger.configure_backend(@backend, opts)
  end

  defp connector() do
    {:ok, connector} = :gen_event.call(Logger, @backend, :connector)
    connector
  end

  defp read_log() do
    connector().read()
  end
end
