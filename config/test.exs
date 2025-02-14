import Config

config :logger,
  backends: []

config :logger, :default_formatter, metadata: ~w(auth crash_reason user_id)a
