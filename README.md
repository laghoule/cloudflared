# Cloudflared Helm Charts

[![Lint and Test Charts](https://github.com/laghoule/cloudflared/actions/workflows/lint-test.yaml/badge.svg)](https://github.com/laghoule/cloudflared/actions/workflows/lint-test.yaml)
[![Release Charts](https://github.com/laghoule/cloudflared/actions/workflows/release.yaml/badge.svg)](https://github.com/laghoule/cloudflared/actions/workflows/release.yaml)

This repository hosts Helm charts, published as a self-hosted Helm chart
repository via GitHub Pages.

## Charts

| Chart | Description |
| --- | --- |
| [`cloudflared`](./charts/cloudflared) | [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) connector (`cloudflared`) with Prometheus metrics, alerting rules and a Grafana dashboard |

See the [chart README](./charts/cloudflared/README.md) for all configuration
options and operating modes.

## Usage

Add this repository to Helm:

```console
helm repo add cloudflared-charts https://laghoule.github.io/cloudflared/
helm repo update
```

Install the chart:

```console
helm install cloudflared cloudflared-charts/cloudflared \
  --namespace cloudflared \
  --create-namespace \
  --set tunnel.token='<TUNNEL_TOKEN>'
```

Prefer an existing Secret over passing the token on the command line:

```console
kubectl create namespace cloudflared
kubectl -n cloudflared create secret generic cloudflared-token \
  --from-literal=tunnelToken='<TUNNEL_TOKEN>'

helm install cloudflared cloudflared-charts/cloudflared \
  --namespace cloudflared \
  --set tunnel.existingSecret=cloudflared-token
```

Alternatively, install directly from a local checkout without adding the
repository:

```console
helm install cloudflared ./charts/cloudflared \
  --namespace cloudflared \
  --create-namespace \
  --set tunnel.token='<TUNNEL_TOKEN>'
```

> The chart requires either a remotely managed tunnel (`tunnel.token` or
> `tunnel.existingSecret`) or a locally managed tunnel (`config.enabled` or
> `config.existingConfigMap`). Rendering fails without one, and also when both
> modes are configured at the same time.

## Repository layout

```
.
├── .github/
│   ├── workflows/
│   │   ├── lint-test.yaml   # ct lint/install on pull requests
│   │   └── release.yaml     # chart-releaser on push to main
│   └── dependabot.yml       # keep GitHub Actions versions up to date
├── charts/
│   └── cloudflared/         # the cloudflared chart
│       ├── ci/              # chart-testing values (no real credentials)
│       ├── dashboards/      # Grafana dashboard JSON
│       ├── templates/
│       ├── values.yaml
│       └── values.schema.json
├── artifacthub-repo.yml.example  # optional Artifact Hub metadata
├── ct.yaml                  # chart-testing configuration
├── CONTRIBUTING.md
└── LICENSE
```

## How releases work

This repository uses [helm/chart-releaser-action](https://github.com/helm/chart-releaser-action):
on every push to `main` that touches `charts/**`, it:

1. Detects any chart whose `version` in `Chart.yaml` was bumped.
2. Packages it (`helm package`) and creates a GitHub Release named
   `<chart>-<version>` with the packaged `.tgz` attached.
3. Updates `index.yaml` on the `gh-pages` branch, which GitHub Pages serves as
   the Helm repository index consumed by `helm repo add`.

Chart-testing (`ct`) runs on pull requests and on pushes to `main` that touch
`charts/**`: it lints the chart, validates `Chart.yaml`, and installs it on an
ephemeral `kind` cluster using the values files under
`charts/cloudflared/ci/`.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for one-time repository setup
(GitHub Pages, workflow permissions), the release process, Artifact Hub
publishing, and local validation instructions.

## AI-assisted development

This chart, its CI/CD workflows, and this documentation were created with
the help of an AI coding agent (OpenCode, using a DeepSeek model), under
human review and direction. Changes were validated with `helm lint`,
`helm template`, `ct lint`, `kubeconform` and JSON Schema validation before
being considered complete. `ct install` runs in CI on an ephemeral `kind`
cluster.

## License

Licensed under the [GNU General Public License v3.0](./LICENSE) (GPLv3).
Note that this repository (the Helm chart packaging) is licensed independently
from the upstream [cloudflare/cloudflared](https://github.com/cloudflare/cloudflared)
project, which has its own license.
