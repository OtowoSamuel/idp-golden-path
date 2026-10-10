# Rebuild Guide — Step-by-Step

This guide reconstructs the IDP Golden Path from scratch. It points you at the
right places and tells you when you're done. No code — just directions.

## How to use these docs

| Doc | What it is |
|---|---|
| `README.md` + `docs/decision-log.md` | The spec — what each piece does and why |
| `docs/build-log.md` | The map — every pitfall you'll hit and how to fix it |
| `docs/medium-article.md` | The story — the publishable narrative + image checklist |
| This guide (`docs/rebuild-guide.md`) | The recipe — ordered steps with checkpoints |
| The committed repo (git) | The answer key — open a file only when stuck; don't copy wholesale |

Work in order. Every step ends with a **checkpoint** — a command that should pass before moving on.

---

## Step 0 — Toolchain

```bash
node --version      # 22+ (24 LTS recommended)
npm --version
terraform --version # 1.7+ (mock_provider tests need it)
kubectl version --client   # only used for `kubectl kustomize`
docker version       # optional until Step 5
git --version
```

Create the workspace and root harness:

```bash
mkdir my-idp && cd my-idp && git init -b main
npm init -y
npm install -D nunjucks          # renderer used by the test harness
```

Reference: root `package.json`, `.gitignore`.

**Gate**: `npm install` succeeds; `.gitignore` excludes `node_modules/`,
`render-output/`, `.terraform/`, `*.tfstate`.

---

## Step 1 — The golden-path skeleton

This is the repo your platform will generate for every service — build it
first because everything else exists to deliver it.

Build these files (in a `templates/service-node/skeleton/` directory):

| File | Must contain |
|---|---|
| `package.json` | `${{ values.service_name }}` / `${{ values.description }}` placeholders; scripts `start/dev/lint/test` (`node --test`); engines `>=22` |
| `src/app.js` | Express 5 app: `/health`, `/ready`, `/metrics` (prom-client), `/api/hello` |
| `src/index.js` | Boots telemetry then the server on `PORT` (default 8080) |
| `src/telemetry.js` | OTel SDK that starts **only** if `OTEL_EXPORTER_OTLP_ENDPOINT` is set (decision log §7: dormant by default) |
| `test/app.test.js` | 3 tests against the app (health/metrics/hello) |
| `eslint.config.js` | Flat config, `@eslint/js` v10 + `globals` v17 |
| `Dockerfile` | Multi-stage `node:24-alpine`, `npm ci --omit=dev`, non-root user, `HEALTHCHECK` via wget |
| `.dockerignore`, `.gitignore`, `README.md` | Generated-repo hygiene + dev docs |

**Pitfalls**: see build log #1 (`node --test` dir arg), #6 (`{% raw %}` comes
in Step 5).

**Gate**: copy the skeleton to a scratch folder, replace placeholders with
literals, then:

```bash
npm install && npm run lint && npm test
```

---

## Step 2 — Deploy manifests (kustomize + Argo CD)

Inside the skeleton, add:

- `deploy/base/` — `kustomization.yaml`, `deployment.yaml`, `service.yaml`,
  `serviceaccount.yaml`. Deployment must carry the golden-path labels
  (`app.kubernetes.io/name`, `team`), probes, and resource limits.
- `deploy/overlays/dev/` — kustomization with a **labeled patch that includes
  `target:`** (build log #2) and the `labels:` block style (not deprecated
  `commonLabels`).
- `deploy/argocd/application-dev.yaml` — `argoproj.io/v1alpha1` Application,
  auto-sync + prune, pointing at the dev overlay.

**Gate**:

```bash
kubectl kustomize templates/service-node/skeleton/deploy/overlays/dev
```

---

## Step 3 — Backstage Software Template

Create `templates/service-node/template.yaml`:

- `apiVersion: scaffolder.backstage.io/v1beta3`
- **Parameters**: name (`^[a-z][a-z0-9-]{2,39}$`), description,
  `OwnerPicker`, `RepoUrlPicker`
- **Steps**: `fetch:template` (from `./skeleton`) → `publish:github` →
  `catalog:register`
- Step inputs use `${{ parameters.x }}`; skeleton files use `${{ values.x }}`
  (different namespaces — don't mix them)
- Plus `templates/service-node/skeleton/catalog-info.yaml` (ownership, links,
  `backstage.io/project-slug`)

Reference the real one, then check yours against it line-by-line instead of
copying.

**Gate**: YAML parses (duplicate-key check — build log #16/#17 for the script
pattern).

---

## Step 4 — The render test (your quality harness)

Write `scripts/render-test.mjs`:

1. Nunjucks env with `tags: { variableStart: '${{', variableEnd: '}}' }`,
   `throwOnUndefined: true`, `autoescape: false`, custom `dump` filter
2. Render every skeleton file into `render-output/<service>/`
3. Assert: no unresolved `${{ }}` placeholders, `package.json` name matches,
   `{% raw %}` blocks survived in `ci.yaml` (build log #6), catalog
   `project-slug` rendered
4. Then actually run the generated repo: `npm ci` → `npm run lint` →
   `npm test` via `execSync` (build log #21 — the README claims this, so make
   it true)

Wire it to `npm test` in the root `package.json`.

**Gate**: `npm test` → *"19 files rendered, lint + unit tests green on output"*.

---

## Step 5 — Lockfile, CI, and signing

1. **Skeleton `package-lock.json`**: generate with `npm install
   --package-lock-only` using placeholder-swapped `package.json`, then put the
   `${{ values.service_name }}` placeholder back into both name fields
   (build log #19 for the exact trap).
2. **`.github/workflows/ci.yaml`** in the skeleton:
   - `lint-and-test` job: checkout, setup-node (node 24, `cache: npm`),
     `npm ci`, lint, test
   - `build-sign-push` job (push only): GHCR login, build-push, **cosign
     keyless** (`cosign sign --yes` + verify with `--certificate-identity-regexp`
     / `--certificate-oidc-issuer`)
   - Permissions: `contents: read`, `packages: write`, `id-token: write` —
     nothing else
   - All Actions **SHA-pinned with `# vX.Y.Z` comments**
   - Everything after the first checkout wrapped in `{% raw %}` (build log #6)

**Gate**: `npm test` still green (it runs `npm ci` against the rendered
lockfile). Optional: `docker build` the rendered output.

---

## Step 6 — Terraform modules

Two modules under `terraform-modules/`:

| Module | Resources |
|---|---|
| `service-baseline` | ECR repo: scan-on-push, image immutability, lifecycle expiration |
| `observability-baseline` | CloudWatch log group + 5xx alarm (disabled by default) |

Each with: `variables.tf` (validation rules), `main.tf`, `outputs.tf`,
`versions.tf` (`required_version >= 1.7.0`, AWS `~> 6.0`), `examples/basic/`,
`tests/main.tftest.hcl` using `mock_provider "aws"`, `README.md`.

Root helper: `scripts/terraform-test.sh` + `npm run test:terraform`.

**Pitfalls**: build log #5 (deprecated region data source), stale lockfiles
after constraint changes.

**Gate**: `npm run test:terraform` → 8/8 passing, no AWS credentials needed.

---

## Step 7 — Admission policy + Backstage wiring

- `policies/kyverno-require-labels.yaml` — **CEL `ValidatingPolicy`**
  (`policies.kyverno.io/v1`, `validationActions: [Deny]`,
  `matchConstraints` on apps workloads, CEL expression requiring both labels).
  Never the legacy `ClusterPolicy` — deprecated v1.19, gone in v1.20
  (build log #11).
- `backstage/app-config.fragment.yaml` — catalog rules/locations, GitHub
  integration, **`guest: {}`** (the only valid way to enable it — build
  log #12).
- `backstage/org.yaml` — demo Groups/Users for OwnerPicker.
- `backstage/README.md` — create-app instructions (`npx
  @backstage/create-app@latest`), fragment merge, token setup.

**Gate**: duplicate-key YAML sweep over all project YAML
(build log #16–18 for a known-good checker script).

---

## Step 8 — Docs

- `README.md` — 8 sections: intro, architecture, quick start, how the template
  works, decisions, measurable results, limitations, demo
- `docs/architecture.md` — mermaid diagram + component table
- `docs/decision-log.md` — numbered decisions, newest first, each with
  decision / why / trade-off
- `docs/build-log.md` — yours, written as you go (this is what became the log
  in this repo)

**Gate**: someone else can run your quick start cold and get green tests.

---

## Step 9 — Currency audit + commit

1. Verify every external version against authoritative sources (build log
   Phase 3: `git ls-remote` for Action tags, npm registry for packages,
   vendor docs for API deprecations)
2. Run the full verification matrix:

```bash
npm test                     # render → install → lint → unit tests
npm run test:terraform       # 8/8 mock tests
kubectl kustomize render-output/payments-api/deploy/overlays/dev
# + optional: docker build/run the rendered output
```

3. Secret-scan the staged tree (`git grep -nIE '(ghp_|github_pat_|AKIA...)'`),
   then `git add -A && git commit`.

**Gate**: clean working tree, everything green, all claims in README true.

---

## Step 10 — Live demo (optional): real Backstage + real signed CI

Proves the story end to end. Full detail: build log Phase 6 (issues 24–31).

```bash
# 1. Backstage next to the repo (Node 24 only — create-app rejects non-LTS)
export PATH="/opt/homebrew/opt/node@24/bin:$PATH"
npx @backstage/create-app@latest --path backstage-app
#    - auth: providers.guest: {}
#    - catalog locations: ../idp-golden-path/templates/service-node/template.yaml (Template)
#                         ../idp-golden-path/backstage/org.yaml (Group)
#                         https://raw.githubusercontent.com/<you>/payments-api/main/catalog-info.yaml
#    - backend.reading.allow: [{ host: raw.githubusercontent.com }]   # issue 28
#    - app.support.items: one real item (empty arrays get dropped — issue 26)

# 2. Install with the @yarnpkg/core pin (issue 24) — root package.json resolutions
yarn install        # ~4 min

# 3. Run backend and frontend SEPARATELY (issue 25 — `yarn start` starves the IPC channel)
export GITHUB_TOKEN=$(gh auth token)
yarn workspace backend start   # :7007
yarn workspace app start       # :3000

# 4. Render the demo service, push it, watch the golden-path CI go green
cd ../idp-golden-path && npm test   # renders → render-output/payments-api (+ lint/tests)
gh repo create <you>/payments-api --public --source render-output/payments-api --push

# 5. Independent signature check
cosign verify ghcr.io/<you>/payments-api@sha256:<digest-from-run> \
  --certificate-identity-regexp "https://github.com/<you>/payments-api/" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

# 6. Screenshots: Playwright script (backstage-app/bs-shots.cjs)
#    guest ENTER → /create → template form (filled) → catalog at /
```

**Gate**: template form renders, generated `payments-api` appears in the catalog with its
owner, CI run green, `cosign verify` passes from outside CI.

---

## Step 11 — Live on AWS (optional): the full path on a real cluster

Everything so far is real but not yet *running*. This step stands up EKS, Argo CD,
Kyverno, and Terraform, and converges the generated service. Full detail + the six
issues it surfaced: build log Phase 7 (issues 32–37).

Checkpoint: `payments-api-dev` is **Synced + Healthy** in Argo CD, the unlabeled Deployment is
**denied** by Kyverno, and `curl http://<elb-dns>/health` returns `{"status":"ok"}`.
If DNS is slow on the LoadBalancer, retry after ~60s. Screenshot examples live in
`docs/assets/screenshots/live/`.

---

## Step 12 — Auto-discovery with ApplicationSet

Instead of manually applying each service's Argo CD Application, use an
ApplicationSet that discovers services automatically from this repo.

**How it works:**

1. The scaffolder tags every new repo with the `golden-path` GitHub topic
   (`addTopics` in the publish step)
2. An ApplicationSet watches `services/` directories in this repo
3. Each `services/<name>/` directory maps to a GitHub repo `OtowoSamuel/<name>`
4. Adding a directory + pushing = auto-deployed service

**Setup:**

```bash
# 1. Create the GitHub token secret (one-time)
export GITHUB_TOKEN=$(gh auth token)
envsubst < argocd/github-token-secret.yaml | kubectl apply -f -

# 2. Apply the ApplicationSet
kubectl apply -f argocd/applicationset.yaml

# 3. For each existing service, add its directory
mkdir -p services/payments-api
echo "repo: payments-api" > services/payments-api/service.yaml
git add services/ && git commit -m "Register payments-api" && git push
```

**To onboard a new service:**

```bash
# After scaffolding via Backstage:
mkdir -p services/<service-name>
echo "repo: <service-name>" > services/<service-name>/service.yaml
git add services/ && git commit -m "Register <service-name>" && git push
# Argo CD picks it up within ~3 minutes (or force refresh)
```

**Gate**: `kubectl get applications -n argocd` shows every service under
`services/`, all Synced + Healthy. New directories appear automatically after push.

**Note**: The `scmProvider` GitHub generator only works with orgs, not user
accounts. The git-based generator used here works with any account.

---

## Verification cheat sheet

| Stage | Command | Pass looks like |
|---|---|---|
| Skeleton | `npm run lint && npm test` (in scratch copy) | 3/3 tests |
| Template | `npm test` (root) | 19 files, lint + tests green |
| Terraform | `npm run test:terraform` | 8/8 |
| Manifests | `kubectl kustomize .../overlays/dev` | YAML output |
| Policy/config | YAML duplicate-key sweep | 0 errors |
| Image (optional) | `docker build` + `curl /health` | `{"status":"ok"}` |
| Live demo (optional) | GitHub Actions run + `cosign verify` | green run, verify passes |
| E2E on AWS (optional) | `kubectl -n argocd get applications` + `curl <elb>/health` | Synced + Healthy, `{"status":"ok"}` |
| Policy (optional) | `kubectl -n dev create deployment rogue --image=nginx` | denied by Kyverno vpol |
