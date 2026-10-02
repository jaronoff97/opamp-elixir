# Run the server in Kubernetes

These manifests run the opamp-elixir server and a Postgres for it in the `opamp` namespace.
Agents in the cluster connect to `ws://opamp-server.opamp.svc:4320/v1/opamp`, and the UI is on
the same port.

| File | What it makes |
|---|---|
| `namespace.yaml` | The `opamp` namespace. |
| `postgres.yaml` | A Postgres 16 StatefulSet with a 1 GiB volume, and its Service `opamp-postgres`. |
| `server.yaml` | The server Deployment (one replica) and its Service `opamp-server` on port 4320. |
| `kustomization.yaml` | Puts it all in the `opamp` namespace and sets the image. |

## The image

The CI workflow `.github/workflows/docker.yml` builds the image for `linux/amd64` and
`linux/arm64`. It pushes `ghcr.io/jaronoff97/opamp-elixir:latest` from `main`, and a version tag
for each `v*` tag.

To build the image yourself:

```sh
# For the architecture of your machine:
docker build -t opamp-elixir:dev .

# For both architectures, and push it to your registry:
docker buildx build --platform linux/amd64,linux/arm64 -t <registry>/opamp-elixir:<tag> --push .
```

To use another image, change `newName` and `newTag` in `kustomization.yaml`, or run
`kustomize edit set image ghcr.io/jaronoff97/opamp-elixir=<image>` in this folder.

## Install

1. Make the namespace and the secrets. The server needs `SECRET_KEY_BASE`, and the server and
   Postgres share `PGPASSWORD`.

   ```sh
   kubectl create namespace opamp
   kubectl -n opamp create secret generic opamp-server \
     --from-literal=SECRET_KEY_BASE="$(openssl rand -base64 48)" \
     --from-literal=PGPASSWORD="$(openssl rand -hex 16)"
   ```

2. Apply the manifests.

   ```sh
   kubectl apply -k deploy/kubernetes
   kubectl -n opamp rollout status statefulset/opamp-postgres
   kubectl -n opamp rollout status deployment/opamp-server
   ```

   The `migrate` init container runs the database migrations before the server starts. The
   server is ready when `/readyz` can query the database.

3. Open the UI.

   ```sh
   kubectl -n opamp port-forward svc/opamp-server 4320
   ```

   Then open <http://localhost:4320>.

4. Point your agents at `ws://opamp-server.opamp.svc:4320/v1/opamp`. For the OpenTelemetry
   Operator OpAMP Bridge, set `spec.endpoint` in its `OpAMPBridge` resource. See
   `docs/opamp-bridge/README.md` for a full bridge setup.

## Configuration

Set these environment variables in `server.yaml`:

| Variable | Default | Meaning |
|---|---|---|
| `PHX_HOST`, `PHX_SCHEME`, `PHX_URL_PORT` | `localhost`, `http`, `PORT` | The public URL of the UI. LiveView accepts browser connections only from it. Behind an ingress, use for example `opamp.example.com`, `https` and `443`. |
| `PORT` | `4320` | The HTTP port for agents and the UI. |
| `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD` | the bundled Postgres | The database. To use your own database, remove `postgres.yaml` from `kustomization.yaml`. |
| `OPAMP_CONNECTION_SETTINGS_FILE` | not set | A ConnectionSettingsOffers JSON file to offer to agents. |
| `OPAMP_CA_CERT_FILE`, `OPAMP_CA_KEY_FILE` | not set | A CA that signs the CSRs that agents send. |
| `OPAMP_TLS_CERT_FILE`, `OPAMP_TLS_KEY_FILE`, `OPAMP_TLS_PORT` | not set, `4321` | An HTTPS listener. With a CA, it verifies agent client certificates. |

To give the server files, for example a CA, put them in a Secret and mount it:

```yaml
# In the server container of server.yaml:
env:
  - name: OPAMP_CA_CERT_FILE
    value: /etc/opamp/ca.crt
  - name: OPAMP_CA_KEY_FILE
    value: /etc/opamp/ca.key
volumeMounts:
  - name: opamp-files
    mountPath: /etc/opamp
    readOnly: true
# In the pod spec:
volumes:
  - name: opamp-files
    secret:
      secretName: opamp-files # kubectl -n opamp create secret generic opamp-files --from-file=ca.crt --from-file=ca.key
```

## Limits

- **One replica.** Each agent's state lives on the node that holds its connection, and the UI
  gets live updates over local PubSub. More replicas need Erlang clustering first, for example
  `DNS_CLUSTER_QUERY` with a headless Service.
- **The Deployment uses the `Recreate` strategy.** An old server deletes its agents when their
  connections close. If old and new servers ran at the same time, the old one could delete the
  agents that had already moved to the new one.
- **The bundled Postgres is for a small setup.** It has one replica and no backups.

## Uninstall

```sh
kubectl delete -k deploy/kubernetes
```

This deletes the `opamp` namespace, and with it the secret and the Postgres volume.
