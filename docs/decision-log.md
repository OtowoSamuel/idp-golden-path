# Decision Log

High-signal rationale for senior interviews. Newest first.

---

## 1. Pin every dependency to current stable (audited Oct 5, 2026)

**Decision**: All external versions pinned to current stable as of October
2026: Node 24 (Active LTS), GitHub Actions `checkout@v7` / `setup-node@v7` /
`docker/*@v7|v4` / `cosign-installer@v4` — all SHA-pinned to the
release commit — plus Cosign v3, AWS provider `~> 6.0`,
Terraform `>= 1.7`, ESLint 10 — and the Kyverno policy written as a CEL
`ValidatingPolicy` (`policies.kyverno.io/v1`), not the deprecated
`kyverno.io/v1 ClusterPolicy`.

**Why**: This repo's premise is "golden path" — stale pins contradict the
claim. Kyverno deprecated `ClusterPolicy` in v1.19 (Aug 2026) and removes it
in v1.20 (Nov 2026); shipping it would mean the policy silently stops working
within one release cycle.

**Trade-off accepted**: Majors move fast (Actions v4→v7, ESLint 9→10).
Pins are re-audited each quarter instead of floating on `@latest`, and CI is
the canary when a pin ages out.

---

## 2. Backstage over Port (portal choice)

**Decision**: Backstage (open-source).

**Why**: It's what job postings discuss by name; the Software Template +
catalog model is the pattern hiring managers recognize. Port is faster to
start but the learning signal ("I built the portal") is weaker, and Backstage
runs fine on a laptop.

**Trade-off accepted**: Backstage setup (app-config, auth, plugins) costs
several days up front. Accepted because portal setup *is* part of the
demonstrated skill.

---

## 3. Template generates a repo; it does not orchestrate infrastructure

**Decision**: The scaffolder only renders files → creates repo → registers
the catalog entry. Terraform and Argo are consumed *by the generated repo*,
not invoked *by the template*.

**Why**: 
- Every step of the template can fail for external reasons (AWS creds,
  cluster availability). Fewer external calls = reliable demos.
- The generated repo is inspectable: a reviewer opens GitHub and sees
  exactly what the platform approved.
- Decoupling means the same modules work for services created outside
  Backstage too.

**Trade-off accepted**: Resources aren't provisioned at click time — the
first `terraform apply` still happens separately (or via a pipeline). For a
starter IDP, a working repo + signed pipeline in <15 min beats fully
provisioned infra that takes an hour.

---

## 4. Cosign keyless (GitHub OIDC) instead of a signing key

**Decision**: `cosign sign --yes` with GitHub's OIDC identity — no key
material anywhere.

**Why**: Key management is the #1 reason teams skip image signing. Keyless
means zero secrets in the repo, and verification ties to the exact
repo/workflow identity.

**Trade-off accepted**: Signing only works from GitHub Actions (needs
`id-token: write`). Local signing would need a real key — acceptable
because CI is where images are built.

---

## 5. One Kyverno policy, not a policy library

**Decision**: A single `require-service-labels` CEL `ValidatingPolicy`
(`validationActions: [Deny]`).

**Why**: The story is "generated services are compliant by construction" —
one policy proves the loop (template adds labels → policy enforces labels).
A library of 30 policies becomes the project instead of the platform.

**Trade-off accepted**: No image-signature admission policy in the demo.
Listed as future work; `cosign verify` at admission is the natural next step
and depends on a cluster we don't run in the repo.

---

## 6. Tests that run with zero cloud credentials

**Decision**: Terraform tests use `mock_provider "aws"`; the template has a
Node render test (`npm test`) that renders the skeleton and asserts on the
output.

**Why**: Portfolio work gets judged by whoever clones it — possibly with no
AWS account. Tests that require credentials don't get run. Both suites run
in seconds, offline.

**Trade-off accepted**: Mock tests verify configuration intent, not real
API behavior. Accepted: module logic is mostly declarative; the risk
is in inputs/outputs, which mocks do validate.

---

## 7. Dormant OpenTelemetry by default

**Decision**: The OTel SDK starts only when `OTEL_EXPORTER_OTLP_ENDPOINT`
is set; otherwise it logs "tracing disabled" and runs.

**Why**: A generated service must start on first run with zero external
dependencies. Hard-failing (or silently buffering) without a collector
would break the <15-minute demo.

**Trade-off accepted**: Observability isn't *proven* in the demo until a
collector exists. The wiring, labels, and Prometheus annotations are
present and inspectable — which is the point of a "hook."

---

## 8. Deliberately left out

| Left out | Why |
|---|---|
| TechDocs (mkdocs per service) | Docs-as-code is real but doubles template maintenance; README covers the demo |
| RBAC / multiple Backstage auth providers | Guest auth is enough for a demo; auth complexity is a config swap, not architecture |
| Terraform remote state backend | Modules are stateless; backend choice belongs to the consuming account |
| Second template (Python) | One proven template > two half-tested ones; the structure makes adding a second trivial |
| Cluster in this repo | Cluster provisioning is Project 1's story; this repo shows the *developer-facing* layer |
