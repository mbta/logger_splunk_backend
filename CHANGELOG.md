CHANGELOG
=========

3.0.0
-----

- BREAKING: Minimum Elixir version is now 1.9.
- fix: don't log unknown messages
- fix: don't crash during DST

2.0.0
-----

- Requests to Splunk now send asynchronously in most cases.
- BREAKING: `max_buffer` is now the maximum number of events to buffer before
  switching to synchronous requests.
- Minimum Elixir version is now 1.7.

1.0.0
-----

- Initial public release.
