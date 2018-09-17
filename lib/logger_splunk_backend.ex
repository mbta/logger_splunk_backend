defmodule Logger.Backend.Splunk do
  @behaviour :gen_event

  @default_format "[$level] $message\n"

  require Logger

  @impl true
  def init({__MODULE__, name}) do
    state = %{
      name: name,
      buffer: [],
      max_buffer: 32,
      buffer_size: 0,
      connector: Logger.Backend.Splunk.Output.Http,
      host: nil,
      level: :debug,
      format: @default_format,
      compiled_format: Logger.Formatter.compile(@default_format),
      metadata: [],
      token: ""
    }
    {:ok, configure([], state)}
  end

  @impl true
  def handle_call({:configure, opts}, state) do
    {:ok, :ok, configure(opts, state)}
  end

  @impl true
  def handle_call(:connector, %{connector: connector} = state) do
    {:ok, {:ok, connector}, state}
  end

  @impl true
  def handle_event({level, _gl, {Logger, msg, ts, md}}, %{level: min_level} = state) do
    state = if is_nil(min_level) or Logger.compare_levels(level, min_level) != :lt do
      log_event(level, msg, ts, md, state)
    else
      state
    end
    {:ok, state}
  end

  @impl true
  def handle_info({:io_reply, _ref, :ok}, state) do
    # ignored
    {:ok, state}
  end
  def handle_info(message, state) do
    Logger.warn(fn -> "#{__MODULE__} unhandled message: #{inspect message}" end)
    {:ok, state}
  end

  defp log_event(level, msg, ts, md, state) do
    data = format_message(msg, level, ts, md, state)
    state = %{
      state |
      buffer: [data | state.buffer],
      buffer_size: state.buffer_size + 1
    }
    maybe_send(state)
  end

  defp format_message(msg, level, ts, md, state) do
    event = format_event(level, msg, ts, md, state)
    map = %{
      event: IO.iodata_to_binary(event),
      sourcetype: "httpevent",
      time: ts_to_unix(ts)
    }
    Jason.encode_to_iodata!(map)
  end

  @unix_epoch :calendar.datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}})
  def ts_to_unix({date, {h, m, s, ms}}) do
    # drop the sub-second value
    gregorian_seconds = :calendar.datetime_to_gregorian_seconds({date, {h, m, s}})
    (gregorian_seconds - @unix_epoch) + (ms / 1000)
  end

  defp format_event(level, msg, ts, md, %{compiled_format: format, metadata: keys}) do
    Logger.Formatter.format(format, level, msg, ts, take_metadata(md, keys))
  end

  def maybe_send(%{buffer_size: bs, max_buffer: mb} = state) when bs >= mb do
    state.connector.transmit(state.buffer, state.host, state.token)
    %{state |
      buffer: [],
      buffer_size: 0
    }
  end
  def maybe_send(state) do
    state
  end

  defp take_metadata(metadata, keys) do
    Enum.reduce(keys, [], fn key, acc ->
      case Keyword.fetch(metadata, key) do
        {:ok, val} -> [{key, val} | acc]
        :error     -> acc
      end
    end) |> Enum.reverse()
  end

  defp configure(opts, state) do
    name = state.name
    env = Application.get_env(:logger, name, [])
    opts = Keyword.merge(env, opts)
    Application.put_env(:logger, name, opts)
    connector = Keyword.get(opts, :connector, state.connector)
    host = Keyword.get(opts, :host, state.host)
    level = Keyword.get(opts, :level, state.level)
    metadata = Keyword.get(opts, :metadata, state.metadata)
    format = Keyword.get(opts, :format, state.format)
    max_buffer = Keyword.get(opts, :max_buffer, state.max_buffer)

    %{state |
      connector: connector,
      host: host,
      level: level,
      format: format,
      max_buffer: max_buffer,
      compiled_format: Logger.Formatter.compile(format),
      metadata: metadata,
      token: token(Keyword.get(opts, :token, ""))
    }
  end

  defp token({:system, envvar}) do
    System.get_env(envvar)
  end
  defp token(binary) when is_binary(binary) do
    binary
  end
end
