# DevOps Technical Exercise – GitOps on local Kubernetes

A tiny web service taken from code to a running deployment on a local Kubernetes
cluster, deployed the GitOps way with Argo CD.

## Plan

| Part | Steps | Status |
|------|-------|--------|
| 0 – Setup | Tools, GitHub repo, this README, Flask app (`/` HTML, `/healthz`), non-root Dockerfile, local build + run | done |
| 1 – Cluster as code | Terraform: kind cluster (1 control-plane + 2 workers), Argo CD + Traefik via Helm; `apply` / `destroy` | done (`apply` + clean `plan` verified; `destroy` not run, the cluster must stay up) |
| 2 – GitOps | `k8s/` manifests (2+ replicas, probes, requests/limits, Ingress), Argo CD Application syncs them; image pulled from public GHCR (instead of the original `kind load` plan, so CI/CD needs no pull secret) | done |
| 3 – CI/CD | GitHub Actions → GHCR tagged by SHA, workflow bumps tag in git, Argo CD rolls out; zero-downtime check | done (3497 requests during a CI rollout, 0 failed) |
| Bonus (if time) | HPA (2–5), Prometheus/Grafana via Argo CD, EKS production notes | todo |

## Tools chosen

| Need | Choice | Why |
|------|--------|-----|
| Containers | Docker Desktop (Windows) | Already used on this machine; kind runs on it |
| Local Kubernetes | kind | Multi-node clusters as Docker containers; lightweight; has a Terraform provider |
| IaC | Terraform + `tehcyx/kind` + `helm` providers | One `apply` creates the cluster and installs the add-ons |
| GitOps | Argo CD (Helm chart) | Required by the exercise |
| Ingress | Traefik (Helm chart) | Simple Helm install, standard `Ingress` support |
| App | Python 3.13 + Flask, served by gunicorn | Small, readable; gunicorn instead of the Flask dev server |
| Editor / agent | VS Code + Claude Code | Prompts saved in [ai-prompts.md](ai-prompts.md) |

## Delivery flow

```
git push main ─▶ GitHub Actions: build image ─▶ push ghcr.io/stavgerti/devops-gitops-exercise:<commit SHA>
                                 └─▶ commit "ci: deploy <sha>" rewriting the image: line in k8s/deployment.yaml
Argo CD (polls git every 60s) ─▶ syncs k8s/ ─▶ Deployment rolling update (maxSurge 1, maxUnavailable 0)
```

CI never talks to the cluster (no `kubectl apply`); git is the only source of truth.

## Part 0 – the app

`app/app.py`:
- `GET /` returns an HTML page with the message (`APP_MESSAGE`), the version (`APP_VERSION`) and the pod name.
- `GET /healthz` returns `200 ok`.
- Pod name comes from `POD_NAME` (set via the Downward API in Kubernetes) or falls back to the hostname, which in Kubernetes is the pod name.

`app/Dockerfile`: `python:3.13-slim`, deps installed first for layer caching, runs as UID `10001` (non-root, numeric so Kubernetes `runAsNonRoot` can verify it). `APP_VERSION` is a build arg baked into the image.

Run locally:

```bash
docker build -t gitops-app:dev --build-arg APP_VERSION=dev app
docker run --rm -p 8080:8080 gitops-app:dev
# http://localhost:8080  and  http://localhost:8080/healthz
```

Tests (run in a throwaway container, nothing installed on the host):

```bash
docker run --rm -v "$PWD/app:/src:ro" -w /src python:3.13-slim sh -c "pip install -q -r requirements.txt pytest && python -m pytest -q -p no:cacheprovider"
```

Verified: `/` → 200 `text/html` with message, version and container hostname; `/healthz` → 200; `id` in the container → `uid=10001(appuser)`; 2 unit tests pass.
