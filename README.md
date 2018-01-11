LoggerSplunkBackend
=======================

## About

A backend for the [Elixir Logger](http://elixir-lang.org/docs/v1.0/logger/Logger.html)
that will send logs to the [Splunk TCP input](https://data.splunkcloud.com).

## Supported options

* **host**: String.t. The hostname of the Splunk endpoint. [default: `data.splunkcloud.com`]
* **port**: Integer. The port number for Splunk. [default: `80`]
* **token**: String.t. The unique Splunk token for the log destination.
* **format**: String.t. The logging format of the message. [default: `[$level] $message\n`].
* **level**: Atom. Minimum level for this backend. [default: `:debug`]
* **metdata**: Keyword.t. Extra fields to be added when sending the logs. These will
be merged with the metadata sent in every log message.

## Using it with Mix

To use it in your Mix projects, first add it as a dependency:

```elixir
def deps do
  [{:logger_splunk_backend, "~> 0.0.1"}]
end
```
Then run mix deps.get to install it.

## Configuration Examples

### Runtime

```elixir
Logger.add_backend {Logger.Backend.Splunk, :debug}
Logger.configure {Logger.Backend.Splunk, :debug},
  host: 'data.Splunk.com',
  port: 10000,
  token: "Splunk-token-goes-here",
  level: :debug,
  format: "[$level] $message\n"
```

### Application config

```elixir
config :logger,
  backends: [{Logger.Backend.Splunk, :error_log}, :console]

config :logger, :error_log,
  host: 'data.Splunk.com',
  port: 10000,
  token: "Splunk-token-goes-here",
  level: :error,
  format: "[$level] $message\n"
```
