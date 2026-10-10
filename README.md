# IDP Golden Path — Internal Developer Platform Starter

> A minimal but production-shaped Internal Developer Platform: one self-service
> template that gives any developer a new service with signed CI, Terraform
> scaffolding, observability hooks, and GitOps readiness — in under 15 minutes.

---

## 1. Problem statement & who this is for

**Problem**: Engineering teams onboard new services by copy-pasting old repos,
manually creating pipelines, and asking the platform person for infrastructure.
The result is inconsistency, security gaps, and slow time-to-first-deploy.

**This is for**:
- Platform / DevOps teams that need a "golden path" — one approved way to
  create a service that already has the right security and delivery defaults.
- Developers who want self-service instead of a ticket queue.
- Hiring managers evaluating whether a candidate can build the platform
  *other engineers use*, not just deploy to it.

## 2. Architecture

See [docs/architecture.md](docs/architecture.md) for the diagram and
component responsibilities. In one line:

```
Developer → Backstage form → template renders golden-path repo →
CI signs the image → Argo CD syncs manifests → catalog shows ownership
```

## 3. Quick start

**Prerequisites**: Node 22+ (CI runs on 24), `kubectl` (for kustomize), Terraform 1.7+, Docker
(optional, for image builds). No AWS account needed to run the tests.

```bash
# 1. Render the skeleton and verify the generated repo works (offline)
npm ci
npm test                          # renders template → lint → unit tests

# 2. Terraform modules: validate + test with mock providers (no AWS creds)
npm run test:terraform

# 3. Run Backstage (separate app, ~10 min one-time)
#    follow backstage/README.md — then click "Create Node.js Service"
```

Repo layout:

```
idp-golden-path/
├── templates/service-node/       # the Software Template + skeleton
│   ├── template.yaml             # Backstage scaffolder recipe
│   └── skeleton/                 # what gets rendered into a new repo
├── terraform-modules/
│   ├── service-baseline/         # ECR repo: scan, immutability, lifecycle
│   └── observability-baseline/   # log group + 5xx alarm
├── backstage/                    # app-config fragments + run guide
├── policies/                     # Kyverno: enforce service labels
├── docs/                         # architecture, decision log, build log, rebuild guide, article
└── scripts/                      # render test + terraform test runner
```

## 4. How the template works (step-by-step)

1. Developer opens **Create → Create Node.js Service** in Backstage.
2. Form validates: name pattern (`^[a-z][a-z0-9-]{2,39}$`), owner picked from
   catalog Groups, repository location picked via `RepoUrlPicker`.
3. **Step 1 — render**: `fetch:template` renders `skeleton/` with the form
   values (`service_name`, `owner`, `destination`, `team_label`). Every file
   and filename is templated.
4. **Step 2 — publish**: `publish:github` creates the private repo and pushes
   the rendered tree to `main`.
5. **Step 3 — register**: `catalog:register` reads `catalog-info.yaml` from
   the new repo — the service appears in the catalog with owner, pipeline
   link, and repo link.
6. The push triggers `.github/workflows/ci.yaml`:
   **lint → test → build → Cosign keyless sign → verify → push to GHCR**.
7. `deploy/argocd/application-dev.yaml` points Argo CD at
   `deploy/overlays/dev`; Argo syncs it into the cluster.

What the generated repo already contains:

| Piece | Purpose |
|---|---|
| `.github/workflows/ci.yaml` | lint, test, build, **cosign sign**, push |
| `Dockerfile` | multi-stage, non-root, healthcheck |
| `deploy/base` + `overlays/dev` | kustomize, probes, resource limits, OTel env |
| `deploy/argocd/application-dev.yaml` | GitOps app, auto-sync + prune |
| `catalog-info.yaml` | ownership, links, lifecycle for the portal |
| `src/telemetry.js` | OTel SDK, dormant until a collector endpoint exists |
| `src/app.js` | `/health`, `/ready`, `/metrics` (Prometheus) |

## 5. Design decisions

The short version:

- **Backstage** — chosen because job postings name it; setup cost accepted.
- **Template generates a repo, doesn't orchestrate infra** — fewer external failure points; the generated repo is inspectable.
- **Cosign keyless** — no signing keys to manage; works only from CI (fine, since CI builds images).
- **Pinned to current stable** — Node 24, SHA-pinned Actions v7, Kyverno CEL policy (audited Oct 5, 2026); a "golden path" with stale pins is self-defeating.
- **One Kyverno policy** — proves the compliance loop instead of becoming a policy project.
- **Tests need no credentials** — mock AWS provider + offline render test, so anyone who clones it gets green tests.
- **Left out**: TechDocs, multi-auth, remote state backend, second language template, cluster provisioning (see decision log).

## 6. What works

- Portal click → signed, working repo: under 15 minutes
- Generated services with Cosign signing: it lives in the template
- Generated services with catalog ownership: rendered, never hand-written
- Reusable Terraform modules (validated + tested): 2 — `service-baseline`, `observability-baseline`
- Template render test (offline): 19 files rendered, lint + 3 unit tests pass on output
- Docker image (rendered repo): builds and serves traffic — `/health` 200, runs as non-root `app`
- Offline tests need zero cloud credentials

## 7. Notes

- **Docker image not built in CI of this repo** — the Dockerfile was verified locally (builds on `node:24-alpine`, serves `/health` as non-root, HEALTHCHECK passes on the rendered repo); add a build check here once this repo has its own CI.
- **No second template (Python)** — structure makes it mechanical to add; one template is proven first.
- **Argo Application must be applied once** (or moved to an app-of-apps repo) — not auto-created by the template.
- **Signing verification at admission** — the Kyverno policy checks labels, not signatures; a Kyverno `ImageValidatingPolicy` is the natural next step.
- **Terraform not invoked by the template** — resources provision when the consumer runs `apply` (decision log explains why).
- **Backstage runs as guest auth** — swap for GitHub auth before any shared deployment.

## 8. Demo

Nine images are committed under `docs/assets/` (2x resolution), captured from the
live systems — checklist for the article is in `docs/medium-article.md`:

| Shot | File | Shows |
|---|---|---|
| Cover | `assets/cover.png` | article cover |
| Architecture | `assets/architecture.png` (+ `architecture-aws.png`) | the flow, mermaid + AWS style |
| Create list | `assets/screenshots/backstage-create.png` | golden-path template card in Backstage |
| Template form | `assets/screenshots/backstage-form.png` | three fields → a golden repo |
| Catalog | `assets/screenshots/backstage-catalog.png` | generated `payments-api` with owner/system |
| Repo | `assets/screenshots/github-repo.png` | pushed repo, green initial commit |
| CI run | `assets/screenshots/github-actions-run.png` | lint + build-sign-push green in 1m 4s |
| Health | `assets/screenshots/service-health.png` | generated service serving `/health` |

The **live deployment set** (EKS `golden-path-demo`, us-east-1, real Argo CD +
Kyverno + Terraform apply) is in `docs/assets/screenshots/live/` — 8 shots covering
the public LoadBalancer `/health`, the Argo app Synced + Healthy, Kyverno deny/allow,
the real AWS resources, cluster runtime, and a fresh Backstage create + catalog.

Live demo steps (Backstage + demo repo + cosign receipt): `docs/rebuild-guide.md` Step 10.
Full AWS E2E (cluster → policy → GitOps → public `/health`): Step 11.

---

**Related**: This is Project 2 of a portfolio. Project 1 (GitOps + policy +
supply chain) is the delivery engine; this repo is the self-service front
door on top of it.
