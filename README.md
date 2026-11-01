# DevOps Technical Exercise – GitOps on local Kubernetes

A tiny web service taken from code to a running deployment on a local Kubernetes
cluster, deployed the GitOps way with Argo CD.

## Plan

| Part | Steps | Status |
|------|-------|--------|
| 0 – Setup | Tools, GitHub repo, this README, Flask app (`/` HTML, `/healthz`), non-root Dockerfile, local build + run | done |
| 1 – Cluster as code | Terraform: kind cluster (1 control-plane + 2 workers), Argo CD + Traefik via Helm; `apply` / `destroy` | done (`apply` + clean `plan` verified; `destroy` not run, the cluster must stay up) |
| 2 – GitOps | `k8s/` manifests (2+ replicas, probes, requests/limits, Ingress), Argo CD Application syncs them; image pulled from public GHCR (instead of the original `kind load` plan, so CI/CD needs no pull secret) | done |
| 3 – CI/CD | GitHub Actions → GHCR tagged by SHA, workflow bumps tag in git, Argo CD rolls out; zero-downtime check | done (3443 requests during a CI rollout, 0 failed, version change seen) |
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
Argo CD (checks git every 60s + jitter) ─▶ syncs k8s/ ─▶ Deployment rolling update (maxSurge 1, maxUnavailable 0)
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

## Part 1 – cluster as code

`terraform/main.tf` (local state, git-ignored):
- `kind_cluster` `gitops`: 1 control-plane + 2 workers, Kubernetes v1.36.4. Host `127.0.0.1:8088` is mapped to Traefik's NodePort `30080`.
- `helm_release` **traefik**: NodePort Service; publishes `localhost` as the Ingress address so Argo CD can mark the Ingress Healthy.
- `helm_release` **argocd**: dex and notifications disabled (unused, saves memory); git checked every 60s.
- `helm_release` **gitops-app** (`argocd-apps` chart): the Argo CD Application for `k8s/`, auto-sync with prune and self-heal. Separate release because it needs the Application CRD from the argo-cd chart.

```bash
cd terraform
terraform init
terraform apply      # ~10 min on a 4 GB Docker VM, mostly image pulls
terraform destroy    # removes the cluster and everything in it
```

Verified: `apply` → 4 resources created, 3 nodes Ready; a second `terraform plan` → no changes.

## Part 2 – GitOps deployment

`k8s/` is synced by Argo CD into namespace `web` (created by Argo CD):
- `deployment.yaml`: 2 replicas; `startupProbe`, `readinessProbe`, `livenessProbe` on `/healthz`; requests 50m/64Mi, limits 500m/128Mi; runs as UID 10001, no privilege escalation, all capabilities dropped; `POD_NAME` from the Downward API.
- `service.yaml`: ClusterIP, port 80 → 8080.
- `ingress.yaml`: class `traefik`, no host rule, so http://localhost:8088 works without editing the hosts file.

```bash
export KUBECONFIG=terraform/gitops-kubeconfig
kubectl -n argocd get applications          # web  Synced  Healthy
kubectl -n web get pods,ingress
# Argo CD UI: https://localhost:8443 (user admin)
kubectl -n argocd port-forward svc/argocd-server 8443:443
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}'   # base64
```

Verified: Application `Synced/Healthy`; http://localhost:8088 opens in the browser and shows the message, the commit SHA as version and the serving pod.

## Part 3 – CI/CD

`.github/workflows/ci.yaml`, on push to `main` that changes `app/**` or the workflow:
1. Run the unit tests in `python:3.13-slim` (the Dockerfile's base image, pytest 9.2.0). A failing test stops the job before anything is pushed or deployed.
2. Log in to GHCR with the built-in `GITHUB_TOKEN` (`packages: write`, `contents: write` only).
3. Build `app/` and push `ghcr.io/stavgerti/devops-gitops-exercise:<commit SHA>`, with `APP_VERSION=<SHA>`.
4. `sed` the `image:` line in `k8s/deployment.yaml`, fail unless exactly one line changed, commit `ci: deploy <sha>` and push.

Argo CD sees the new commit and does a rolling update. The deploy commit only touches `k8s/`, so it does not retrigger the workflow.
The GHCR package is public with no manual visibility change (the repo is public): checked with an anonymous registry token (manifest → 200) and a `docker pull` with empty credentials. The image contains only `app.py`, `requirements.txt` and the base image's environment.

Zero downtime: `maxSurge: 1` / `maxUnavailable: 0`, readiness gating, and a 5s `preStop` sleep so Traefik stops routing to a pod before it gets SIGTERM.

```bash
python tests/zero_downtime.py http://127.0.0.1:8088/ 420   # ~10 req/s
# meanwhile: change the message in app/app.py, commit, push
```

The script passes (exit 0) only if no request failed **and** at least two different versions were seen, so a loop that missed the rollout fails.

Verified:
- Message changed and pushed (`8d6f11d`) → CI green → bot commit `8b8737d` → Argo CD rolled out the new image → 3497 requests, 0 failed, version switched mid-loop (before the two-version check existed).
- With the unit-test step and the two-version check (`4f2fcf4`): CI ran `2 passed`, then built and pushed → bot commit `5aa1efe` → Argo CD rolled out → **3443 requests, 0 failed, 2 version(s) seen, exit 0**. Raw output: [tests/zero_downtime_result.txt](tests/zero_downtime_result.txt).

## Submission summary

**Finished:** Part 0, Part 1, Part 2 and Part 3, each verified as described above. The cluster is left running.

**Missing:** the bonuses (HPA, Prometheus/Grafana via Argo CD, EKS notes). `terraform destroy` is written but was not run on the final cluster, which must stay up.

**One decision and why:** the image comes from a public GHCR package, and CI deploys by committing the new tag to git. The first plan was `kind load` of a local image. Our GitHub-hosted runner cannot reach the local kind cluster directly in this setup, so we chose GHCR plus GitOps through Argo CD. Alternatives exist, such as a self-hosted runner on this machine, but this solution does not need them. A private package would need a pull secret in the cluster. With a public image and a commit to git, the cluster needs no credentials, CI needs no access to the cluster, and git history shows what is deployed.

**Where the AI was wrong:** the initial Deployment written by the AI agent (Claude Code) had only liveness and readiness probes, with `initialDelaySeconds: 10` on liveness and a 200m CPU limit. That setup caused pod restarts. After the first sync the Application was `Synced/Healthy`, but both pods showed `RESTARTS 1`. The pod and event checks run during the work (`kubectl get pods`, `kubectl get events`) showed `Container web failed liveness probe, will be restarted`. Gunicorn starting under 200m, on nodes still busy with Argo CD, took longer than the liveness probe allowed. The agent then added a `startupProbe` and raised the CPU limit to 500m, and the change was deployed through git and Argo CD. The re-check showed the new pods with 0 restarts and 0 failed requests out of 1239 during that rollout.

A second case was found in my code review of the repo. The AI-written workflow built, pushed and deployed without running the unit tests. Also, `zero_downtime.py` returned success even if no version change happened during the loop, so a run that missed the rollout looked like a pass. The fix adds a unit-test step before the GHCR login, build and push, and makes the script fail unless at least two versions were seen. Before pushing, both were checked locally: the test command passes on the app and fails on a copy with a broken `/healthz`, and the script exits 1 when no rollout happens. After pushing, the CI run showed `2 passed` before the build, and the rollout test passed with 3443 requests, 0 failed, 2 versions.
