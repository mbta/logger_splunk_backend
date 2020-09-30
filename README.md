LoggerSplunkBackend
=======================

## About

A backend for the [Elixir Logger](https://hexdocs.pm/logger/1.7.4/Logger.html)
that will send logs to the [Splunk cloud](https://data.splunkcloud.com) HTTP Event Collector (HEC).

It may also work for on-prem installations of Splunk, but that has not been tested.

## Supported options

* **host**: String.t. The URL of the Splunk HEC endpoint.
* **token**: String.t. The unique Splunk token.
* **index**: String.t. (optional) The Splunk index to log to.
* **format**: String.t. The logging format of the message. [default: `"[$level] $message"`].
* **level**: Atom.t. Minimum level for this backend. [default: `:debug`]
* **metadata**: Keyword.t | `:all`. Extra fields to be added when sending the logs. These will
be merged with the metadata sent in every log message. (default: `[]`)
* **max_buffer**: pos_integer. The number of messages to buffer before switching to a synchronous request.

## Using it with Mix

To use it in your Mix projects, first add it as a dependency:

```elixir
def deps do
  [{:logger_splunk_backend, "~> 2.0.0"}]
end
```
Then run mix deps.get to install it.

## Configuration Examples

### Runtime

```elixir
Logger.add_backend {Logger.Backend.Splunk, :debug}
Logger.configure {Logger.Backend.Splunk, :debug},
  host: "https://https-inputs-XXX.splunkcloud.com/services/collector",
  token: "Splunk-token-goes-here",
  level: :debug,
  format: "[$level] $message\n"
```

### Application config

```elixir
config :logger,
  backends: [{Logger.Backend.Splunk, :error_log}, :console]

config :logger, :error_log,
  host: "https://https-inputs-XXX.splunkcloud.com/services/collector",
  token: "Splunk-token-goes-here",
  level: :error,
  format: "[$level] $message\n"
```

## Log Examples

A log message such as `Logger.info("here is a message")` results in the following Splunk request:

```json
{
  "host": "node_sname@host",
  "event": "[info] here is a message",
  "time": 123456.789,
  "sourcetype": "httpevent"
}
```
