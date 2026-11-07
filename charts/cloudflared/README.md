# cloudflared Helm chart

Helm chart to deploy [cloudflared](https://github.com/cloudflare/cloudflared),
the **Cloudflare Tunnel** connector, on Kubernetes.

The chart provides:

- a cloudflared `Deployment` with health probes and graceful shutdown;
- support for both **remotely managed tunnels** (token) and **locally managed
  tunnels** (`config.yaml` + credentials + ingress);
- a Prometheus metrics server, plus optional `Service`, `ServiceMonitor` and
  alerting rules;
- a ready-to-use **Grafana dashboard**, shipped as a `ConfigMap` and
  auto-loaded by the kube-prometheus-stack dashboard sidecar;
- an optional `PodDisruptionBudget`.

## Requirements

- Kubernetes >= 1.23
- Helm >= 3.8
- For `metrics.serviceMonitor.enabled` and `metrics.prometheusRule.enabled`:
  the [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator)
  CRDs
- For dashboard auto-import: Grafana with the dashboard sidecar enabled
  (installed by default with kube-prometheus-stack)

## Operating modes

Two mutually exclusive modes are supported:

| Mode | Values | Description |
| --- | --- | --- |
| Token (recommended) | `tunnel.token` or `tunnel.existingSecret` | The tunnel and its ingress rules are managed from the Cloudflare dashboard. |
| Local config | `config.enabled` or `config.existingConfigMap` | The tunnel is defined by a `config.yaml` file (UUID, credentials, ingress). |

The chart deliberately fails at render time when no mode is configured, or
when both modes are configured at the same time.

> Cloudflare recommends at least 2 replicas per tunnel (maximum 25 replicas,
> for 100 connections). The chart defaults to `replicaCount: 2`. Setting
> `replicaCount: 0` scales the connector down without uninstalling the release.

## Quick start (remotely managed tunnel)

Add the chart repository:

```bash
helm repo add cloudflared-charts https://laghoule.github.io/cloudflared/
helm repo update
```

Install the chart:

```bash
helm install cloudflared cloudflared-charts/cloudflared \
  --namespace cloudflared \
  --create-namespace \
  --set tunnel.token='<TUNNEL_TOKEN>'
```

From a local checkout, replace `cloudflared-charts/cloudflared` with
`./charts/cloudflared` (from the repository root).

### Recommended: token in an existing Secret

This avoids storing the token in Helm values:

```bash
kubectl create namespace cloudflared

kubectl -n cloudflared create secret generic cloudflared-token \
  --from-literal=tunnelToken='<TUNNEL_TOKEN>'

helm install cloudflared cloudflared-charts/cloudflared \
  --namespace cloudflared \
  --set tunnel.existingSecret=cloudflared-token
```

If the Secret key is not `tunnelToken`:

```bash
--set tunnel.existingSecret=cloudflared-token \
--set tunnel.tokenKey=token
```

## Locally managed tunnel

### 1. Create the credentials Secret

```bash
kubectl -n cloudflared create secret generic cloudflared-credentials \
  --from-file=credentials.json=./<TUNNEL_ID>.json
```

### 2. Create a values file

```yaml
# values-local.yaml
config:
  enabled: true
  tunnelID: "6ff42ae2-765d-4adf-8112-31c55c1551ef"

  credentials:
    existingSecret: cloudflared-credentials
    key: credentials.json

  ingress:
    - hostname: app.example.com
      service: http://my-app.default.svc.cluster.local:80
    - hostname: ssh.example.com
      service: ssh://my-server.default.svc.cluster.local:22
    # Catch-all rule is mandatory
    - service: http_status:404
```

```bash
helm install cloudflared cloudflared-charts/cloudflared -n cloudflared -f values-local.yaml
```

The `config.yaml` file is generated into a `ConfigMap`. It contains the tunnel
UUID, the path to the credentials mounted in the pod, and the ingress rules.

### Variants

- **Existing ConfigMap**: `config.existingConfigMap=my-config` (the ConfigMap
  must contain a `config.yaml` key).
- **Inline credentials**: `config.credentials.file` accepts the raw credentials
  JSON (not base64). The Secret is then created by the chart. This is not
  recommended for production; prefer an existing Secret.
- **Full config file**: `config.configFile` lets you provide the entire
  `config.yaml`. `config.tunnelID` is then no longer required.
- **Extra options**: `config.extraConfig` adds root keys to the generated
  `config.yaml` (`originRequest`, `warp-routing`, etc.).

## Metrics and monitoring

cloudflared exposes its Prometheus metrics on `0.0.0.0:2000/metrics`
(configurable through `metrics.port`). The startup and readiness probes use
`/ready`, which reflects the connection to the Cloudflare edge. The liveness
probe uses `/metrics`, so a Cloudflare-side outage does not restart the pods.

```yaml
metrics:
  enabled: true
  port: 2000
  service:
    enabled: true
  serviceMonitor:
    enabled: true          # requires the ServiceMonitor CRD
    interval: 30s
    scrapeTimeout: 10s
    labels:
      release: kube-prometheus-stack
  prometheusRule:
    enabled: true          # requires the PrometheusRule CRD
    labels:
      release: kube-prometheus-stack
```

The `ServiceMonitor` selects the `<name>-metrics` Service. The `PrometheusRule`
installs three default alerts:

- `CloudflaredNoActiveConnection`: no active HA connection for 5 minutes;
- `CloudflaredHighErrorRate`: more than 5% failed requests for 10 minutes;
- `CloudflaredHeartbeatRetries`: unacknowledged heartbeats for 10 minutes.

The default rules aggregate by `namespace` and `service`, so each tunnel alerts
independently and the alert names the affected tunnel. See
[Multiple releases](#multiple-releases) when you run several tunnels.

> HTTP probes require the metrics server. When `metrics.enabled=false`, the
> probes are disabled automatically.

## Grafana dashboard

The **"Cloudflared / Tunnel overview"** dashboard is included in the chart at
`dashboards/cloudflared.json`. It is embedded into a `ConfigMap` when
`grafana.dashboards.enabled=true` (the default).

The dashboard UID, title and `ConfigMap` key are derived from the release name,
so several releases can ship their own dashboard without colliding in Grafana.
A release named `cloudflared` gets the UID `cloudflared-overview` and the title
`Cloudflared / Tunnel overview`; any other release `<name>` gets the UID
`<name>-cloudflared-overview` and the title
`Cloudflared / Tunnel overview (<name>-cloudflared)`. UIDs longer than 40
characters (the Grafana limit) are truncated and suffixed with a short hash.
When `metrics.serviceMonitor.enabled=true`, the `job` and `namespace` variables
default to the release's metrics Service and namespace.

The kube-prometheus-stack sidecar discovers it automatically through the
`grafana_dashboard: "1"` label. If Grafana only watches a single namespace,
place the ConfigMap in that namespace:

```bash
helm upgrade cloudflared . -n cloudflared \
  --reuse-values \
  --set grafana.dashboards.namespace=monitoring
```

The dashboard includes:

- summary indicators: edge connections, connectors, requests/s, error rate,
  concurrent requests, active streams;
- traffic and errors by pod;
- TCP/UDP sessions;
- QUIC connectivity (RTT, lost packets);
- heartbeats and edge locations;
- Go runtime (goroutines, heap) and Prometheus scrape health.

Available variables: Prometheus data source, `job`, `namespace` and `pod`. The
metrics are filtered by the Prometheus `job` label, which is the Service name
when scraping through the `ServiceMonitor`. Pick the matching `job` value if you
scrape with another setup.

To import it manually:

```bash
kubectl -n monitoring get configmap cloudflared-grafana-dashboard \
  -o json | jq -r '.data | to_entries[0].value' > cloudflared.json
```

Then in Grafana: **Dashboards → New → Import → Upload JSON**.

## Multiple releases

Several releases can run side by side, in the same namespace or in different
ones. Every resource name is prefixed with the release name, and the Service,
ServiceMonitor and PodDisruptionBudget select pods by `app.kubernetes.io/instance`.

```bash
helm install tunnel-a cloudflared-charts/cloudflared -n cloudflared \
  --set tunnel.token='<TOKEN_A>' \
  --set metrics.serviceMonitor.enabled=true

helm install tunnel-b cloudflared-charts/cloudflared -n cloudflared \
  --set tunnel.token='<TOKEN_B>' \
  --set metrics.serviceMonitor.enabled=true \
  --set metrics.prometheusRule.enabled=false
```

Keep in mind:

- **Dashboards**: each release creates its own dashboard, with a distinct UID and
  title. Set `grafana.dashboards.enabled=false` on the releases that do not need
  one. A single dashboard can also cover every tunnel through its `job`,
  `namespace` and `pod` variables.
- **Alerts**: the default rules cover every cloudflared tunnel scraped by the
  same Prometheus. Enable `metrics.prometheusRule` on **one** release only,
  otherwise each alert is defined twice. If you override `rules`, keep the
  `by (namespace, service)` aggregation so each tunnel is evaluated separately.
- **Grafana namespace**: with `grafana.dashboards.namespace` set, all dashboards
  land in that namespace. Their names stay unique because they include the
  release name, but the release names must differ.

## Graceful shutdown and availability

- `gracePeriod` (default `30s`) is passed to `cloudflared`: in-flight
  connections get this long to complete on SIGTERM.
- `terminationGracePeriodSeconds` (default `60`) must remain greater than
  `gracePeriod`.
- The deployment strategy is `maxUnavailable: 0` / `maxSurge: 1`.
- The `PodDisruptionBudget` (default `minAvailable: 1`) is only created when
  `replicaCount > 1`.

## Values validation

The chart ships a `values.schema.json` file (JSON Schema draft-07). Helm
validates the merged values against it before rendering, which catches typos and
invalid settings early:

- unknown top-level or nested keys are rejected;
- types, enums and ranges are enforced (`replicaCount` 0-25, `logLevel`,
  `protocol`, `image.pullPolicy`, `metrics.port` 1-65535, Go durations,
  percentage-based rolling update values, and so on);
- each ingress rule must define a `service`;
- each Prometheus rule must define an `expr`, plus either `alert` or `record`;
- `extraEnv` entries must define a `name`, and `extraVolumeMounts` entries must
  define both `name` and `mountPath`.

Invalid values fail with an explicit message, for example:

```text
Error: values don't meet the specifications of the schema(s) in the following chart(s):
cloudflared:
- at '/replicaCount': maximum: got 26, want 25
- at '/image/pullPolicy': value must be one of 'Always', 'IfNotPresent', 'Never'
```

If you need to pass a value that the schema does not allow yet, update
`values.schema.json` together with the templates.

## Values

| Parameter | Description | Default |
| --- | --- | --- |
| `replicaCount` | Number of cloudflared replicas (`0` scales down) | `2` |
| `image.repository` | cloudflared image | `cloudflare/cloudflared` |
| `image.tag` | Image tag | `""` (appVersion) |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `imagePullSecrets` | Image pull secrets | `[]` |
| `nameOverride` | Override the chart name | `""` |
| `fullnameOverride` | Override the full name | `""` |
| `serviceAccount.create` | Create a ServiceAccount | `true` |
| `serviceAccount.automount` | Mount the ServiceAccount token | `false` |
| `serviceAccount.annotations` | ServiceAccount annotations | `{}` |
| `serviceAccount.name` | ServiceAccount name | `""` |
| `podAnnotations` | Pod annotations | `{}` |
| `podLabels` | Pod labels | `{}` |
| `podSecurityContext` | Pod security context | see `values.yaml` |
| `securityContext` | Container security context | see `values.yaml` |
| `resources` | Container resources | `{}` |
| `nodeSelector` | Node selector | `{}` |
| `tolerations` | Tolerations | `[]` |
| `affinity` | Affinity | `{}` |
| `topologySpreadConstraints` | Topology spread constraints | `[]` |
| `priorityClassName` | priorityClassName | `""` |
| `terminationGracePeriodSeconds` | Kubernetes grace period | `60` |
| `updateStrategy` | Deployment strategy | RollingUpdate 0/1 |
| `logLevel` | cloudflared log level | `info` |
| `protocol` | Protocol to Cloudflare (`auto`, `http2`, `quic`) | `auto` |
| `gracePeriod` | In-flight connection grace period | `30s` |
| `extraArgs` | Extra `run` arguments | `[]` |
| `extraEnv` | Extra environment variables | `[]` |
| `extraEnvFrom` | Environment variables from ConfigMaps/Secrets | `[]` |
| `extraVolumes` | Extra volumes | `[]` |
| `extraVolumeMounts` | Extra volume mounts | `[]` |
| `tunnel.token` | Remotely managed tunnel token | `""` |
| `tunnel.existingSecret` | Existing token Secret | `""` |
| `tunnel.tokenKey` | Token key inside the Secret | `tunnelToken` |
| `config.enabled` | Enable local config mode | `false` |
| `config.existingConfigMap` | Existing ConfigMap (`config.yaml`) | `""` |
| `config.tunnelID` | Tunnel UUID | `""` |
| `config.configFile` | Full `config.yaml` content | `""` |
| `config.ingress` | Ingress rules | `[]` |
| `config.extraConfig` | Extra root keys | `{}` |
| `config.credentials.file` | Raw credentials JSON | `""` |
| `config.credentials.existingSecret` | Existing credentials Secret | `""` |
| `config.credentials.key` | Credentials key | `credentials.json` |
| `metrics.enabled` | Enable the metrics server | `true` |
| `metrics.port` | Metrics and `/ready` port | `2000` |
| `metrics.service.enabled` | Create the metrics Service | `true` |
| `metrics.service.type` | Service type | `ClusterIP` |
| `metrics.service.annotations` | Service annotations | `{}` |
| `metrics.serviceMonitor.enabled` | Create a ServiceMonitor | `false` |
| `metrics.serviceMonitor.interval` | Scrape interval | `30s` |
| `metrics.serviceMonitor.scrapeTimeout` | Scrape timeout | `10s` |
| `metrics.serviceMonitor.labels` | ServiceMonitor labels | `{}` |
| `metrics.serviceMonitor.relabelings` | Relabelings | `[]` |
| `metrics.serviceMonitor.metricRelabelings` | Metric relabelings | `[]` |
| `metrics.prometheusRule.enabled` | Create Prometheus alerts | `false` |
| `metrics.prometheusRule.labels` | PrometheusRule labels | `{}` |
| `metrics.prometheusRule.annotations` | PrometheusRule annotations | `{}` |
| `metrics.prometheusRule.rules` | Alerting rules | 3 alerts |
| `probes.enabled` | Enable HTTP probes | `true` |
| `probes.startup.periodSeconds` | Startup probe period | `5` |
| `probes.startup.failureThreshold` | Startup failure threshold | `30` |
| `probes.readiness.periodSeconds` | Readiness period | `10` |
| `probes.readiness.failureThreshold` | Readiness failure threshold | `3` |
| `probes.liveness.periodSeconds` | Liveness period | `10` |
| `probes.liveness.failureThreshold` | Liveness failure threshold | `3` |
| `tests.enabled` | Create the `helm test` metrics check | `true` |
| `grafana.dashboards.enabled` | Create the dashboard ConfigMap | `true` |
| `grafana.dashboards.label` | Grafana sidecar label | `grafana_dashboard` |
| `grafana.dashboards.labelValue` | Label value | `"1"` |
| `grafana.dashboards.namespace` | ConfigMap namespace | `""` (release) |
| `grafana.dashboards.annotations` | ConfigMap annotations | `{}` |
| `podDisruptionBudget.enabled` | Create a PDB (when > 1 replica) | `true` |
| `podDisruptionBudget.minAvailable` | Minimum available pods | `1` |

## Security

- The container runs as non-root (`65532`), with a read-only root filesystem,
  `allowPrivilegeEscalation: false` and all capabilities dropped.
- cloudflared does not need the Kubernetes API: the ServiceAccount token mount
  is disabled by default.
- Always prefer `tunnel.existingSecret` or `config.credentials.existingSecret`
  to avoid exposing secrets in Helm values.

## Development

Run these commands from the repository root:

```bash
# Lint both operating modes (the chart requires a tunnel mode)
helm lint charts/cloudflared -f charts/cloudflared/ci/token-values.yaml
helm lint charts/cloudflared -f charts/cloudflared/ci/config-values.yaml

# Render manifests
helm template cloudflared charts/cloudflared \
  -f charts/cloudflared/ci/token-values.yaml

# Validate the rendered Kubernetes manifests
helm template cloudflared charts/cloudflared \
  -f charts/cloudflared/ci/token-values.yaml \
  | kubeconform -strict -summary -skip ServiceMonitor,PrometheusRule -

# Test metrics connectivity inside the cluster (requires running connector pods)
helm test cloudflared -n cloudflared
```

## Uninstall

```bash
helm uninstall cloudflared -n cloudflared
```

The tunnel and any routes remain managed on the Cloudflare side. Delete them from the Cloudflare dashboard if needed.
