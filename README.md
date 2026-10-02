# OpAMPServer

This app needs the Elixir and Erlang versions in `.tool-versions` (Elixir 1.20, Erlang/OTP 29),
Node.js for the config editor, and PostgreSQL.

To start your Phoenix server:

  * Run `npm install --prefix assets` to install the config editor (CodeMirror)
  * Run `mix setup` to install and setup dependencies
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4320`](http://localhost:4320), the default OpAMP port, from your browser:

  * **Fleet** (`/`): a graph of this server, every connected agent, and the collectors that each
    OpAMP Bridge manages.
  * **Agents** (`/agents`): the list of agents. Each agent page (`/agents/:id`) has an overview,
    a config editor, a graph of the collector pipelines, and its connection settings.
  * **Settings** (`/settings`): this server's configuration.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

This is an elixir implementation of the opamp-specification

## Connection settings

The server can offer connection settings to agents and sign their client certificates. All of
these environment variables are optional:

  * `OPAMP_CONNECTION_SETTINGS_FILE` - a `ConnectionSettingsOffers` as proto3 JSON, for example
    `{"ownMetrics": {"destinationEndpoint": "https://otlp:4318"}}`. Each part goes only to agents
    with the matching capability.
  * `OPAMP_CA_CERT_FILE` and `OPAMP_CA_KEY_FILE` - a CA that signs (and auto-approves) agent CSRs.
  * `OPAMP_TLS_CERT_FILE`, `OPAMP_TLS_KEY_FILE` and `OPAMP_TLS_PORT` (default 4321) - an HTTPS
    listener. With a CA, it verifies the client certificates that the CA issued.

## Generating the protos

The protos come from [opamp-spec](https://github.com/open-telemetry/opamp-spec) and are generated with
`protoc-gen-elixir` at the same version as the `protobuf` dependency in `mix.exs`. Upstream uses the package
`opamp.proto.v1`; we rewrite it to `opamp.proto` so the modules stay `Opamp.Proto.*` (the wire format is the same).

```
cp -r <path-to-opamp-spec-repo>/proto /tmp/opamp-src
sed -i '' 's/^package opamp\.proto\.v1;/package opamp.proto;/' /tmp/opamp-src/opamp/v1/*.proto
protoc -I /tmp/opamp-src --elixir_out=/tmp/opamp-out /tmp/opamp-src/opamp/v1/opamp.proto /tmp/opamp-src/opamp/v1/anyvalue.proto
cp /tmp/opamp-out/opamp/proto/opamp/v1/*.pb.ex lib/opamp_server_web/protobufs/
```


## Learn more

  * Official website: https://www.phoenixframework.org/
  * Guides: https://hexdocs.pm/phoenix/overview.html
  * Docs: https://hexdocs.pm/phoenix
  * Forum: https://elixirforum.com/c/phoenix-forum
  * Source: https://github.com/phoenixframework/phoenix
