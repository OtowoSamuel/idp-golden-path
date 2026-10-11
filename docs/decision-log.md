# Decision Log

Rationale for the choices made while building this Internal Developer Platform starter. Newest first.

## 0. ApplicationSet with git generator over scmProvider or manual apply

Decision: Use an Argo CD ApplicationSet with a `git` generator that watches `services/*` directories in this repo, instead of `scmProvider.github` or manual `kubectl apply` per service.

Why:
- **Manual apply doesn't scale** — every new service needs a cluster-side action, which defeats the "golden path" promise.
- **`scmProvider.github` requires a GitHub org** — it hardcodes `/orgs/<org>/repos`; user accounts return 404. No `user` field exists in the CRD.
- **Git generator works with any account type** — it scans directories, not the GitHub API. Each `services/<name>/` directory maps to `github.com/<owner>/<name>`.

Trade-off: Someone must create the `services/<name>/` directory and push. This is a deliberate friction point — it means deploying to the cluster is an explicit, reviewable git commit, not an automatic side effect of scaffolding. The `golden-path` topic is also added by the scaffolder for hygiene and future org migration.

## 1. Pin every dependency to current stable (audited Oct 2026)

All external versions pinned to current stable as of October 2026: Node 24 (Active LTS), GitHub Actions `checkout@v7` / `setup-node@v7` / `docker/*@v7|v4` / `cosign-installer@v4` — all SHA-pinned to the release commit — plus Cosign v3, AWS provider `~> 6.0`, Terraform `>= 1.7`, ESLint 10 — and the Kyverno policy written as a CEL `ValidatingPolicy` (`policies.kyverno.io/v1`), not the deprecated `kyverno.io/v1 ClusterPolicy`.

This repo's premise is "golden path" — stale pins contradict the claim. Kyverno deprecated `ClusterPolicy` in v1.19 (Aug 2026) and removes it in v1.20 (Nov 2026); shipping it would mean the policy silently stops working within one release cycle.

Pins are re-audited each quarter instead of floating on `@latest`, and CI is the canary when a pin ages out.

## 2. Backstage over portal choice

Decision: Backstage (open-source).

Why: It's the most widely adopted developer portal standard — the Software Template + catalog model is what most platform teams converge on. Port is faster to start but Backstage has a larger ecosystem, more plugins, and runs fine on a laptop.

Trade-off accepted: Backstage setup (app-config, auth, plugins) costs several days up front. Accepted because the setup itself is part of building a real platform, not just a demo.

## 3. Template generates a repo; it does not orchestrate infrastructure

Decision: The scaffolder only renders files → creates repo → registers the catalog entry. Terraform and Argo are consumed *by the generated repo*, not invoked *by the template*.

Why: 
- Every step of the template can fail for external reasons (AWS creds not available, rate limits, DNS propagation). Keeping the template self-contained means the generated repo is inspectable and the platform has fewer failure points.
- Infrastructure is the consumer's responsibility — the generated repo ships with Terraform modules the operator runs when ready.

Trade-off: The generated repo doesn't provision infra instantly. Accepted because a working, signed repo in under 15 minutes (portal click → first green run) beats half-provisioned infrastructure.
