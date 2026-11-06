# Contributing

This document is for maintainers and contributors of this Helm chart
repository — not for end users of the `cloudflared` chart (see the main
[README.md](./README.md) and [charts/cloudflared/README.md](./charts/cloudflared/README.md)
for that).

Chart content (values, templates, documentation, dashboards) must be written in
English.

## One-time repository setup

These steps must be performed once, in the GitHub repository settings, by
whoever administers this repo (they can't be done from chart files alone):

1. **Push this repository to GitHub**, with `main` as the default branch.
2. **Workflow permissions:** in *Settings → Actions → General → Workflow
   permissions*, select **"Read and write permissions"**. Do this *before* the
   first push/run — the release workflow needs it to push to the `gh-pages`
   branch and create releases using the default `GITHUB_TOKEN`.
3. **Create the `gh-pages` branch once:** `chart-releaser` v1.9+ fails with
   `invalid reference: origin/gh-pages` when the branch does not exist. Create
   an empty orphan branch from a local clone:

   ```console
   git checkout --orphan gh-pages
   git rm -rf . >/dev/null
   git commit --allow-empty -m "Initialize gh-pages"
   git push origin gh-pages
   git checkout main
   ```

4. **First release:** manually trigger the **Release Charts** workflow from the
   *Actions* tab (`workflow_dispatch`), or push a change under `charts/**`.
   `chart-releaser` then creates the release and tag, and writes `index.yaml`
   to `gh-pages`.
5. **Enable GitHub Pages:** in *Settings → Pages*, set **Source** to
   **"Deploy from a branch"**, branch **`gh-pages`**, folder **`/ (root)`**.
   (This option only appears once `gh-pages` exists, i.e. after step 3.)
6. The chart repository is then served at
   `https://laghoule.github.io/cloudflared/`.

The repository name and Pages URL above assume this repository is named
`cloudflared` under the `laghoule` account. If you publish it under a different
owner or name, update the badges and URLs in `README.md`, the URLs in this file,
and the GitHub Pages URL in `charts/cloudflared/README.md`.

### Troubleshooting: no release / empty `index.yaml`

If the **Release Charts** run finishes green but no GitHub Release or tag
appears, and `gh-pages` doesn't contain an `index.yaml`, it's almost always
step 2 above being done *after* the run (permissions were still read-only when
`chart-releaser` tried to push). Fix:

1. Confirm *Settings → Actions → General → Workflow permissions* is set to
   **"Read and write permissions"**.
2. If a `gh-pages` branch already exists but was created manually (e.g. it's
   just a copy of `main` instead of an orphan branch with `index.yaml`),
   delete it (*Settings → Branches*, or `git push origin --delete gh-pages`).
3. Re-run the **Release Charts** workflow from the *Actions* tab (**Run
   workflow**, thanks to its `workflow_dispatch` trigger) — `chart-releaser`
   will recreate `gh-pages` correctly.
4. Re-point *Settings → Pages* at the freshly created `gh-pages` branch.

## Continuous integration

`.github/workflows/lint-test.yaml` runs [chart-testing](https://github.com/helm/chart-testing)
(`ct`) on pull requests and on pushes to `main` that touch `charts/**`:

1. `ct lint` validates `Chart.yaml` conventions (version bump, maintainers),
   lints the chart with every `charts/cloudflared/ci/*-values.yaml` file, and
   validates the rendered YAML.
2. `ct install` installs the chart on an ephemeral `kind` cluster for each CI
   values file, then runs `helm test`.

The `ci/` values files exist because the chart intentionally refuses to render
without a tunnel mode. They exercise both operating modes without requiring real
Cloudflare credentials:

- `ci/token-values.yaml` uses a placeholder token in a Secret;
- `ci/config-values.yaml` uses a fake tunnel UUID, fake credentials and sample
  ingress rules;
- both set `replicaCount: 0` so no connector tries to reach Cloudflare, and
  `tests.enabled: false` because the metrics test needs a running pod.

Do not put real credentials in `ci/` — those files are committed and packaged
in CI runs.

## Cutting a new release

1. Bump `version` (and `appVersion`, if the underlying cloudflared release
   changed) in `charts/cloudflared/Chart.yaml`.
2. Open a PR — CI (`lint-test.yaml`) will run `ct lint`/`ct install` against it.
3. Merge to `main` — `release.yaml` then packages the chart, creates a GitHub
   Release, and updates `index.yaml` on `gh-pages`.

### Note: pushes that don't bump the version

`release.yaml` triggers on **any** push to `main` touching `charts/**`, not
just version bumps (e.g. a `README.md` or `values.yaml` fix without a version
change). `chart-releaser` is configured with `skip_existing: true`, so in that
case it just detects that a release for the current version already exists and
skips it (no-op, workflow still shows green). If you see the run fail instead of
skipping, check that `skip_existing` is still set in `release.yaml` — without
it, `chart-releaser` errors out instead of skipping when trying to re-publish an
existing version.

## Optional: Artifact Hub

Artifact Hub publication is optional and disabled by default. To enable it:

1. Add the repository in the [Artifact Hub control panel](https://artifacthub.io/control-panel/repositories)
   (kind "Helm charts", URL `https://laghoule.github.io/cloudflared/`).
2. Copy `artifacthub-repo.yml.example` to `artifacthub-repo.yml` and replace
   `repositoryID` with the ID shown by Artifact Hub.
3. Commit and push to `main`. The release workflow publishes
   `artifacthub-repo.yml` to `gh-pages`; Artifact Hub then indexes the chart
   automatically.

The `Publish artifacthub-repo.yml` step is a no-op while
`artifacthub-repo.yml` does not exist.

## Local validation

```console
# Lint with CI values (the chart fails without a tunnel mode by design)
helm lint charts/cloudflared -f charts/cloudflared/ci/token-values.yaml
helm lint charts/cloudflared -f charts/cloudflared/ci/config-values.yaml

# Render both modes
helm template cloudflared charts/cloudflared -f charts/cloudflared/ci/token-values.yaml
helm template cloudflared charts/cloudflared -f charts/cloudflared/ci/config-values.yaml

# Validate the rendered Kubernetes manifests
helm template cloudflared charts/cloudflared \
  -f charts/cloudflared/ci/token-values.yaml \
  | kubeconform -strict -summary -

# Package the chart
helm package charts/cloudflared -d /tmp/cloudflared-chart
```

To reproduce the chart-testing run locally, use its official Docker image:

```console
docker run --rm -it -v "$(pwd)":/workdir --workdir /workdir \
  quay.io/helmpack/chart-testing:v3.15.0 \
  ct lint --target-branch main

docker run --rm -it -v "$(pwd)":/workdir --workdir /workdir \
  --network host \
  quay.io/helmpack/chart-testing:v3.15.0 \
  ct install --target-branch main
```

(`ct install` needs a reachable Kubernetes cluster — e.g. point `KUBECONFIG`
at a local `kind`/`minikube` cluster.)

The Grafana dashboard and the Prometheus alert rules can be syntax-checked with
`promtool check rules`; both use only standard PromQL.
