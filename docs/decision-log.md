# Decision Log

Rationale for the choices made while building this Internal Developer Platform starter. Newest first.

## 1. Pin every dependency to current stable (audited Oct 2026)

All external versions pinned to current stable as of October 2026: Node 24 (Active LTS), GitHub Actions `checkout@v7` / `setup-node@v7` / `docker/*@v7|v4` / `cosign-installer@v4` — all SHA-pinned to the release commit — plus Cosign v3, AWS provider `~> 6.0`, Terraform `>= 1.7`, ESLint 10 — and the Kyverno policy written as a CEL `ValidatingPolicy` (`policies.kyverno.io/v1`), not the deprecated `kyverno.io/v1 ClusterPolicy`.

This repo's premise is "golden path" — stale pins contradict the claim. Kyverno deprecated `ClusterPolicy` in v1.19 (Aug 2026) and removes it in v1.20 (Nov 2026); shipping it would mean the policy silently stops working within one release cycle.

Pins are re-audited each quarter instead of floating on `@latest`, and CI is the canary when a pin ages out.

## 2. Backstage over portal choice

Decision: Backstage (open-source).

Why: It's what job postings discuss by name; the Software Template + catalog model is the pattern hiring managers recognize. Port is faster to start but the learning signal ("I built the portal") is weaker, and Backstage runs fine on a laptop.

Trade-off accepted: Backstage setup (app-config, auth, plugins) costs several days up front. Accepted because portal setup *is* part of the demonstrated skill.

## 3. Template generates a repo; it does not orchestrate infrastructure

Decision: The scaffolder only renders files → creates repo → registers the catalog entry. Terraform and Argo are consumed *by the generated repo*, not invoked *by the template*.

Why: 
- Every step of the template can fail for external reasons (AWS creds not available, rate limits, DNS propagation). Keeping the template self-contained means the generated repo is inspectable and the platform has fewer failure points.
- Infrastructure is the consumer's responsibility — the generated repo ships with Terraform modules the operator runs when ready.

Trade-off: The generated repo doesn't provision infra instantly. Accepted because a working, signed repo in under 15 minutes (portal click → first green run) beats half-provisioned infrastructure.
