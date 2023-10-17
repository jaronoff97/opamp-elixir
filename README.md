# OpAMPServer

To start your Phoenix server:

  * Run `mix setup` to install and setup dependencies
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

This is an elixir implementation of the opamp-specification

## Generating the protos

To update the generated protos, from the root of this repository run the following:
```
protoc --elixir_out=./protobufs --proto_path=<path-to-opamp-spec-repo>/proto anyvalue.proto
protoc --elixir_out=./protobufs --proto_path=<path-to-opamp-spec-repo>/proto opamp.proto
```


## Learn more

  * Official website: https://www.phoenixframework.org/
  * Guides: https://hexdocs.pm/phoenix/overview.html
  * Docs: https://hexdocs.pm/phoenix
  * Forum: https://elixirforum.com/c/phoenix-forum
  * Source: https://github.com/phoenixframework/phoenix
