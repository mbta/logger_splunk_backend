defmodule Logger.Backend.Splunk do
  @behaviour :gen_event

  @default_format "[$level] $message\n"

  require Logger

  @impl :gen_event
  def init({__MODULE__, name}) do
    state = %{
      name: name,
      buffer: [],
      max_buffer: 32,
      buffer_size: 0,
      response: nil,
      output: nil,
      printing_response?: false,
      error_device: :stdio,
      erlang_host_json: ~s("host":""),
      host: nil,
      level: :debug,
      format: @default_format,
      compiled_format: Logger.Formatter.compile(@default_format),
      metadata: [],
      token: ""
    }

    {:ok, configure([], state)}
  end

  @impl :gen_event
  def handle_call({:configure, opts}, state) do
    {:ok, :ok, configure(opts, state)}
  end

  @impl :gen_event
  def handle_event({level, _gl, {Logger, msg, ts, md}}, state) do
    %{level: min_level, buffer_size: buffer_size, max_buffer: max_buffer, response: response} =
      state

    cond do
      not meet_level?(level, min_level) ->
        {:ok, state}

      is_nil(response) ->
        # we aren't in the middle of a request, so send the message right away
        {:ok, log_event(level, msg, ts, md, state)}

      buffer_size < max_buffer ->
        # we are in the middle of a request, but there's still room to
        # buffer. we'll send these messages when the current one completes,
        # from handle_http_event/2.
        {:ok, buffer_event(level, msg, ts, md, state)}

      true ->
        # we're in the middle of the request, but have reached our max buffer size
        state = buffer_event(level, msg, ts, md, state)
        {:ok, await_response(state)}
    end
  end

  def handle_event(:flush, state) do
    {:ok, await_response(state)}
  end

  @impl :gen_event
  def handle_info(%{id: ref} = response, %{response: %{id: ref}} = state) do
    {:ok, handle_http_response(response, state)}
  end

  def handle_info({:io_reply, _ref, _result}, state) do
    # ignored
    {:ok, state}
  end

  def handle_info({:EXIT, _pid, _reason}, state) do
    # ignored
    {:ok, state}
  end

  def handle_info(message, state) do
    IO.puts(state.error_device, [
      "ERROR ",
      inspect(__MODULE__),
      " unhandled message: ",
      inspect(message)
    ])

    {:ok, state}
  end

  defp handle_http_response(%HTTPoison.AsyncStatus{code: 200}, state) do
    state
  end

  defp handle_http_response(%HTTPoison.AsyncStatus{code: invalid}, state) do
    IO.puts(state.error_device, [
      "ERROR unexpected status code when logging to Splunk: ",
      inspect(invalid),
      "\n",
      "ERROR sent: ",
      state.output
    ])

    %{state | printing_response?: true}
  end

  defp handle_http_response(%HTTPoison.AsyncHeaders{}, state) do
    state
  end

  defp handle_http_response(%HTTPoison.AsyncChunk{}, %{printing_response?: false} = state) do
    state
  end

  defp handle_http_response(
         %HTTPoison.AsyncChunk{chunk: body},
         %{printing_response?: true} = state
       ) do
    IO.puts(state.error_device, ["ERROR response: ", body])
    state
  end

  defp handle_http_response(%HTTPoison.AsyncEnd{}, state) do
    maybe_send(%{state | response: nil, output: nil, printing_response?: false})
  end

  defp handle_http_response(%HTTPoison.Error{reason: reason}, state) do
    IO.puts(state.error_device, [
      "ERROR unable to log to Splunk: ",
      inspect(reason),
      "\n",
      "ERROR sent: ",
      state.output
    ])

    maybe_send(%{state | response: nil, output: nil, printing_response?: false})
  end

  defp meet_level?(_level, nil) do
    true
  end

  defp meet_level?(level, min_level) do
    Logger.compare_levels(level, min_level) != :lt
  end

  defp log_event(level, msg, ts, md, state) do
    state = buffer_event(level, msg, ts, md, state)
    maybe_send(state)
  end

  defp buffer_event(level, msg, ts, md, state) do
    data = format_message(msg, level, ts, md, state)

    %{
      state
      | buffer: [state.buffer, data],
        buffer_size: state.buffer_size + 1
    }
  end

  @spec format_message(iodata, Logger.level(), Logger.Formatter.time(), Logger.metadata(), map) ::
          iodata
  @doc "Given a log message (and various metadata), return a JSON event as an iolist."
  def format_message(msg, level, ts, md, state) do
    event = format_event(level, msg, ts, md, state)
    # ensure the event is properly escaped
    event_json = Jason.encode_to_iodata!(IO.iodata_to_binary(event))
    # ensure we encode the timestamp without using scientific notation. if we
    # do, then it breaks splunk with an "Error in handling indexed fields"
    ts_float =
      :erlang.float_to_binary(
        ts_to_unix(ts),
        [:compact, decimals: 3]
      )

    # build the raw JSON as an IOlist
    [
      "{",
      state.erlang_host_json,
      ~s["event":],
      event_json,
      ~s[,"time":],
      ts_float,
      ~s[,"sourcetype":"httpevent"}]
    ]
  end

  @unix_epoch :calendar.datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}})
  defp ts_to_unix({date, {h, m, s, ms}}) do
    # drop the sub-second value and convert to POSIX time
    {date, time} = :erlang.localtime_to_universaltime({date, {h, m, s}})
    gregorian_seconds = :calendar.datetime_to_gregorian_seconds({date, time})
    gregorian_seconds - @unix_epoch + ms / 1000
  end

  defp format_event(level, msg, ts, md, %{compiled_format: format, metadata: keys}) do
    Logger.Formatter.format(format, level, msg, ts, take_metadata(md, keys))
  end

  defp maybe_send(%{response: nil, buffer_size: bs} = state) when bs != 0 do
    case send_to_splunk(state) do
      {:ok, response} ->
        %{state | response: response, output: state.buffer, buffer: [], buffer_size: 0}

      {:error, %{reason: reason}} ->
        IO.puts(state.error_device, [
          "ERROR unable to connect to Splunk: ",
          inspect(reason),
          "\n",
          "ERROR sent: ",
          state.buffer
        ])

        %{state | buffer: [], buffer_size: 0}
    end
  end

  defp maybe_send(state) do
    state
  end

  defp send_to_splunk(state) do
    headers = [{"Authorization", "Splunk #{state.token}"}, {"Content-Type", "application/json"}]
    opts = [hackney: [pool: :logger_splunk_backend], stream_to: self()]
    HTTPoison.post(state.host, state.buffer, headers, opts)
  end

  defp await_response(%{response: %{id: ref}} = state) do
    receive do
      %{id: ^ref} = response ->
        state = handle_http_response(response, state)
        await_response(state)
    end
  end

  defp await_response(state) do
    maybe_send(state)
  end

  defp take_metadata(metadata, keys) do
    Enum.reduce(keys, [], fn key, acc ->
      case Keyword.fetch(metadata, key) do
        {:ok, val} -> [{key, val} | acc]
        :error -> acc
      end
    end)
    |> Enum.reverse()
  end

  defp configure(opts, state) do
    name = state.name
    env = Application.get_env(:logger, name, [])
    opts = Keyword.merge(env, opts)
    Application.put_env(:logger, name, opts)
    host = Keyword.get(opts, :host, state.host)
    level = Keyword.get(opts, :level, state.level)
    metadata = Keyword.get(opts, :metadata, state.metadata)
    format = Keyword.get(opts, :format, state.format)
    max_buffer = Keyword.get(opts, :max_buffer, state.max_buffer)
    error_device = Keyword.get(opts, :error_device, state.error_device)

    %{
      state
      | host: host,
        level: level,
        format: format,
        max_buffer: max_buffer,
        compiled_format: Logger.Formatter.compile(format),
        metadata: metadata,
        token: token(Keyword.get(opts, :token, "")),
        error_device: error_device,
        erlang_host_json: [~s("host":), Jason.encode_to_iodata!(Atom.to_string(node())), ","]
    }
  end

  defp token({:system, envvar}) do
    System.get_env(envvar)
  end

  defp token(binary) when is_binary(binary) do
    binary
  end
end
