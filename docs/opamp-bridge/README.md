# Runbook: the OpAMP Bridge against opamp-elixir in OrbStack Kubernetes

This runbook runs the OpenTelemetry Operator OpAMP Bridge in the OrbStack Kubernetes cluster. The
bridge connects to an opamp-elixir server that runs on the Mac host. Then the runbook confirms that
the two work together in both directions:

- The bridge reports its collectors to the server: description, effective config, and health.
- The server sends a remote config, and the bridge creates and updates collectors from it.

The files in this folder are the exact manifests and script that the runbook uses.

Versions on the last run (2026-10-02): OrbStack Kubernetes v1.35.6, opentelemetry-operator Helm
chart 0.124.1 (operator 0.160.0), bridge image `operator-opamp-bridge:latest` (version 0.160.0), and
the server on Elixir 1.20.4, Erlang/OTP 29.1.1, Phoenix 1.8.15 and LiveView 1.2.12.

## Prerequisites

- OrbStack, with Docker.
- `kubectl` and `helm`.
- Elixir and Erlang from `.tool-versions` in the repository root.

Your kubeconfig can contain other clusters. To keep every command on the local cluster, each
command in this runbook sets `--context orbstack` or `--kube-context orbstack`.

## 1. Start OrbStack Kubernetes

```sh
orb start k8s
kubectl --context orbstack get nodes
```

The node `orbstack` must show `Ready`.

## 2. Pull the latest bridge image

```sh
docker pull ghcr.io/open-telemetry/opentelemetry-operator/operator-opamp-bridge:latest
docker image inspect ghcr.io/open-telemetry/opentelemetry-operator/operator-opamp-bridge:latest \
  --format '{{index .Config.Labels "org.opencontainers.image.version"}}'
```

OrbStack Kubernetes uses the Docker image store of the host. Thus the pulled image is available to
the cluster, and `bridge.yaml` sets `imagePullPolicy: IfNotPresent`.

## 3. Install the OpenTelemetry Operator

The operator runs the bridge from an `OpAMPBridge` resource, and it runs the collectors. The chart
can make its own webhook certificate, so cert-manager is not necessary.

```sh
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update open-telemetry
helm --kube-context orbstack install opentelemetry-operator open-telemetry/opentelemetry-operator \
  --version 0.124.1 \
  -n opentelemetry-operator-system --create-namespace \
  --set admissionWebhooks.certManager.enabled=false \
  --set admissionWebhooks.autoGenerateCert.enabled=true \
  --set manager.opampBridgeImage.repository=ghcr.io/open-telemetry/opentelemetry-operator/operator-opamp-bridge \
  --set manager.opampBridgeImage.tag=latest \
  --wait --timeout 5m
kubectl --context orbstack -n opentelemetry-operator-system get pods
```

The operator pod must show `Running`.

## 4. Start the opamp-elixir server on the host

1. Start Postgres. The dev config expects `postgres:postgres` on `localhost:5432`.

   ```sh
   docker run -d --rm --name opamp-test-pg -e POSTGRES_PASSWORD=postgres -p 5432:5432 postgres:16
   ```

2. Make the database. Run these commands from the repository root.

   ```sh
   npm install --prefix assets   # first time only
   mix setup                     # first time only
   mix ecto.create
   mix ecto.migrate
   ```

3. Start the server as a named node. Step 7 uses the node name to call into the server.

   ```sh
   elixir --sname opamp -S mix phx.server
   ```

The server listens on `127.0.0.1:4320`. The UI is at <http://localhost:4320>.

4. Make sure that a pod can reach the server.

   ```sh
   kubectl --context orbstack run nettest --rm -i --restart=Never --image=curlimages/curl -- \
     curl -s -o /dev/null -w "%{http_code}\n" --max-time 5 http://host.orb.internal:4320/
   ```

   The result must be `200`. In OrbStack, `host.orb.internal` reaches the Mac host from a pod, also
   for a server that listens only on `127.0.0.1`.

## 5. Deploy the bridge and a managed collector

```sh
kubectl --context orbstack apply \
  -f docs/opamp-bridge/rbac.yaml \
  -f docs/opamp-bridge/collector.yaml \
  -f docs/opamp-bridge/bridge.yaml
kubectl --context orbstack -n default get pods,opampbridge,otelcol
```

- `rbac.yaml` gives the `opamp-bridge` service account access to collectors, pods, and workloads.
- `collector.yaml` makes the collector `default/simplest`. Its `opentelemetry.io/opamp-managed:
  "true"` label lets the bridge report it and change it.
- `bridge.yaml` makes the bridge, with the endpoint `ws://host.orb.internal:4320/v1/opamp`.

The pods `opamp-bridge-opamp-bridge-*` and `simplest-collector-*` must show `Running`.

## 6. Confirm that the bridge reports to the server

In the server log, find one `JOINED agents:<id>` line. After about 30 seconds, `HANDLED heartbeat`
lines start.

To read what the server stored, call into the server node:

```sh
elixir --sname driver --rpc-eval "opamp@$(hostname -s)" '
for a <- OpAMPServer.Agents.list_agent() do
  IO.puts("agent #{a.id}")
  IO.puts("  service.name=#{OpAMPServerWeb.AgentLive.Show.find_description_field(a.description, "service.name")}")
  IO.puts("  effective config keys=#{inspect(Map.keys(a.effective_config.config_map.config_map))}")
  IO.puts("  healthy=#{a.component_health.healthy}")
end'
```

Expected result:

```
agent <instance uid>
  service.name=io.opentelemetry.operator-opamp-bridge
  effective config keys=["default/simplest"]
  healthy=true
```

Open <http://localhost:4320> to see the bridge and `default/simplest` in the Fleet graph. The agent
page is at `http://localhost:4320/agents/<instance uid>`.

## 7. Confirm that the server manages collectors through the bridge

`push-remote-config.exs` sets a desired remote config on each connected agent. The config updates
`default/simplest`: it adds `memory_limiter` to its pipeline. The config also makes a new collector,
`default/from-server`. The server channel then sends the config to the bridge.

```sh
elixir --sname driver --rpc-eval "opamp@$(hostname -s)" "$(cat docs/opamp-bridge/push-remote-config.exs)"
kubectl --context orbstack -n default get otelcol,pods
kubectl --context orbstack -n default get otelcol simplest \
  -o jsonpath='{.spec.config.service.pipelines.traces.processors}'
```

Expected result:

- `otelcol` shows `from-server` and `simplest`, both `1/1` and `managed`.
- The processors of `simplest` are `["memory_limiter","batch"]`.
- The bridge log shows `Creating collector` for `from-server` and `Updating collector` for
  `simplest`:

  ```sh
  kubectl --context orbstack -n default logs deploy/opamp-bridge-opamp-bridge
  ```

After the next heartbeat, the server has the result of the config:

```sh
elixir --sname driver --rpc-eval "opamp@$(hostname -s)" '
[a] = OpAMPServer.Agents.list_agent()
IO.puts("keys=#{inspect(Map.keys(a.effective_config.config_map.config_map))}")
IO.puts("status=#{a.remote_config_status.status}")
IO.puts("hash matches=#{a.remote_config_status.last_remote_config_hash == a.desired_remote_config.config_hash}")'
```

Expected result:

```
keys=["default/from-server", "default/simplest"]
status=RemoteConfigStatuses_APPLIED
hash matches=true
```

## 8. Optional: confirm a reconnect

```sh
kubectl --context orbstack -n default rollout restart deploy/opamp-bridge-opamp-bridge
```

The server log shows a second `JOINED` line, for the new instance uid of the new pod. The server
has one agent, and the server log has no `[error]` or `[warning]` lines.

## Known problems

- **The RBAC in the upstream README is not sufficient.** The bridge 0.160.0 does not start without
  `get` on `deployments`, `daemonsets`, and `statefulsets`. The error is `missing get permission for
  apps/deployments: access denied`. `rbac.yaml` includes these rules.
- **A remote config must list each managed collector.** The bridge deletes a managed collector if
  the remote config does not include its key. When the bridge starts, it also counts the collectors
  that already have the managed label. For this reason, a save on the agent page sends all the
  managed collectors that the agent reports, and also the desired config
  (`OpAMPServer.Agents.config_map_with/3`). A script that sets the remote config, like
  `push-remote-config.exs`, must also list each managed collector.
- **The server forgets the desired config on a disconnect.** The server deletes the agent row when
  the connection closes. A bridge that reconnects keeps its collectors, but the server does not
  have the desired config any longer.

## Teardown

```sh
kubectl --context orbstack delete \
  -f docs/opamp-bridge/bridge.yaml \
  -f docs/opamp-bridge/rbac.yaml
kubectl --context orbstack -n default delete otelcol simplest from-server
helm --kube-context orbstack uninstall opentelemetry-operator -n opentelemetry-operator-system
kubectl --context orbstack delete namespace opentelemetry-operator-system
docker stop opamp-test-pg
```

Stop the server with `Ctrl-C` twice. To stop the Kubernetes cluster, use `orb stop k8s`.
