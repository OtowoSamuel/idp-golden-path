# Build Log

Everything done to get this project from empty folder to its current state:
phases, commands run, issues hit, and how each was fixed. Chronological.

- **Project**: Internal Developer Platform (IDP) Starter — "idp-golden-path"
- **Dates**: built and audited against releases current as of **October 5, 2026**
- **Environment**: macOS (darwin), zsh, Node 25 (local), Terraform 1.15.3, Docker Desktop

---

## Phase 1 — Scaffold the project

Created the full structure offline-testable by design:

```
templates/service-node/     Backstage Software Template (scaffolder v1beta3) + skeleton
terraform-modules/          service-baseline (ECR), observability-baseline (logs/alarm)
backstage/                  app-config fragment, org.yaml, run guide
policies/                   Kyverno label policy
deploy (in skeleton)        kustomize base/overlay + Argo CD Application
docs/                       architecture.md (mermaid), decision-log.md
scripts/                    render-test.mjs, terraform-test.sh
```

Key syntax decisions made up front (later verified against docs):

- Skeleton files use Backstage's Nunjucks dialect: `${{ values.x }}`
- GitHub Actions expressions in skeleton files wrapped in `{% raw %}...{% endraw %}`
  so templating doesn't eat `${{ github.* }}` / `${{ secrets.* }}`
- Template steps use `${{ parameters.x }}`; filters `parseRepoUrl`, `parseEntityRef`

### Issues faced in Phase 1 (and fixes)

| # | Issue | Symptom | Fix |
|---|-------|---------|-----|
| 1 | `node --test test/` fails on modern Node | Node 25 rejects directory argument | `npm test` → plain `node --test` (auto-discovers `test/`) |
| 2 | Kustomize overlay patch missing target | `kubectl kustomize` error | Added `target:` selector to JSON patch in `deploy/overlays/dev/kustomization.yaml` |
| 3 | Duplicate YAML key `locations:` | Config invalid on merge | Merged the two `locations:` blocks into one in `backstage/app-config.fragment.yaml` |
| 4 | Invented config key `scaffolder.defaultOrganization` | Not a real Backstage key | Removed |
| 5 | Deprecated Terraform data source | `data.aws_region.current.name` deprecated | Removed (region passed as variable) |
| 6 | `{% raw %}` gotcha | Render test failed: Actions expressions were "eaten" | Wrapped all GH Actions blocks in `{% raw %}`; render test now asserts `github.actor` / `secrets.GITHUB_TOKEN` survive |
| 7 | Docker daemon not running | Dockerfile unverified | Documented as known limitation in README §7 (closed in Phase 3) |

---

## Phase 2 — First full verification

Ran everything; fixed assertion mismatches as they surfaced:

```bash
npm test                                  # render test
npm run test:terraform                    # terraform validate + mock tests ×2 modules
kubectl kustomize render-output/payments-api/deploy/overlays/dev
# python heredoc: duplicate-key sweep over all project YAML
```

Issues and fixes:

| # | Issue | Fix |
|---|-------|-----|
| 8 | Render test asserted `${{ values.service_name }}` — wording didn't match output | Tightened assertion |
| 9 | ci.yaml assertion needed to check raw-block survival | Asserts `github.actor`, `secrets.GITHUB_TOKEN`, `cosign sign` presence |

Result: 18 files rendered, 8/8 Terraform mock tests, kustomize OK, YAML clean.

---

## Phase 3 — Currency audit (everything vs Oct 5, 2026 releases)

Verified each external dependency against authoritative sources instead of
assuming. Findings → fixes.

### 3a. Research commands

```bash
# exact GitHub Action tags (authoritative — from the repos themselves)
git ls-remote https://github.com/actions/checkout.git        refs/tags/v7.0.1
git ls-remote https://github.com/actions/setup-node.git      refs/tags/v7.0.0
git ls-remote https://github.com/docker/login-action.git     refs/tags/v4.6.0
git ls-remote https://github.com/docker/build-push-action.git refs/tags/v7.4.0
git ls-remote https://github.com/sigstore/cosign-installer.git refs/tags/v4.1.2

# web research (webfetch / websearch):
#   - Kyverno policy types (docs URL 404'd — see issue #11)
#   - Backstage guest auth provider config keys
#   - npm registry latest versions (eslint, globals, express, prom-client, OTel)
```

### 3b. Issues faced

| # | Issue | Symptom | Fix |
|---|-------|---------|-----|
| 10 | Kyverno docs URL `kyverno.io/docs/policy-types/` → **404** | Couldn't fetch CEL schema | Used websearch; found schema at `main.kyverno.io/docs/policy-types/validating-policy/` + migration guide |
| 11 | **Deprecated `ClusterPolicy`** (`kyverno.io/v1`) | Deprecated Kyverno v1.19 (Aug 2026), removed v1.20 (Nov 2026) | Rewrote policy as CEL `ValidatingPolicy` (`policies.kyverno.io/v1`): `validationActions: [Deny]`, `matchConstraints`, CEL `validations` |
| 12 | **Invalid Backstage guest auth keys** | `enabled: true` / `allowOutsideOfVisitor: true` don't exist — Backstage would fail config validation | Verified via Backstage docs → `guest: {}` (+ commented `dangerouslyAllowOutsideDevelopment`) |
| 13 | **zsh word-splitting bug** in SHA-fetch loop | `set -- $spec` doesn't split in zsh → `Malformed input to a URL function` from `git ls-remote` | Used zsh param expansion: `repo="${spec%% *}"; tag="${spec##* }"` |
| 14 | Annotated-tag vs commit SHA ambiguity | Pinning needs the **commit** SHA | Queried `refs/tags/X^{}` as well; confirmed all 5 tags were lightweight → SHAs are commit SHAs |

### 3c. Fixes applied

**Backstage** (`backstage/app-config.fragment.yaml`):

```yaml
auth:
  providers:
    guest: {}    # was: enabled/allowOutsideOfVisitor (nonexistent keys)
```

**Kyverno** (`policies/kyverno-require-labels.yaml`) — full migration:

```yaml
apiVersion: policies.kyverno.io/v1        # was kyverno.io/v1 ClusterPolicy
kind: ValidatingPolicy                    # was ClusterPolicy
spec:
  validationActions: [Deny]               # was validationFailureAction: Enforce
  matchConstraints:                       # was rules[].match.any[].resources
    resourceRules:
      - apiGroups: [apps]
        apiVersions: [v1]
        operations: [CREATE, UPDATE]
        resources: [deployments, statefulsets, daemonsets]
  validations:
    - expression: >
        has(object.metadata.labels) &&
        'app.kubernetes.io/name' in object.metadata.labels &&
        'team' in object.metadata.labels
      message: Workloads must be labeled with app.kubernetes.io/name and team.
```

**Skeleton CI** (`.github/workflows/ci.yaml`):

| Was | Now |
|-----|-----|
| `actions/checkout@v4` | `@3d3c42e5…90b1 # v7.0.1` (SHA-pinned, Phase 4) |
| `actions/setup-node@v4`, node 22 | `@v7`, node 24 (Active LTS Oct 2026) |
| `docker/login-action@v3` | `@v4.6.0` |
| `docker/build-push-action@v6` | `@v7.4.0` |
| `sigstore/cosign-installer@v3` | `@v4.1.2` (required for Cosign v3) |
| `attestations: write` | removed (unused — no attest step) |

**Skeleton runtime**: Dockerfile `node:22-alpine` → `node:24-alpine`;
`engines >=20` → `>=22` (Node 20 EOL'd Mar 2026); eslint `^9` → `^10.12.0`,
`@eslint/js` → `^10.0.1`, `globals` → `^17.13.0`.

**Terraform** (both modules + examples):

```hcl
required_version = ">= 1.7.0"   # was >= 1.5.0 — mock_provider needs 1.7
version = "~> 6.0"              # was >= 5.0 — pin major per AWS guidance
```

Stale `.terraform.lock.hcl` files (pinned to old constraints) deleted → regenerated.

**Docs**: README prereqs (Node 22+, TF 1.7+), `verifyImages` → `ImageValidatingPolicy`
(policies move to `ImageValidatingPolicy` in the CEL migration), new decision-log
entry #1 "Pin every dependency (audited Oct 5, 2026)", cross-references renumbered.

| # | Issue | Fix |
|---|-------|-----|
| 15 | Decision-log renumber loop re-hit the newly inserted heading | Two `## 3.` headings appeared → fixed manually to `## 2.` |

### 3d. Re-verification after audit

```bash
npm test                                   # 19→18 files then; all render assertions pass
(cd render-output/payments-api && rm -rf node_modules && npm install && npm run lint && npm test)
npm run test:terraform                     # 8/8 pass on AWS provider 6.x
kubectl kustomize render-output/payments-api/deploy/overlays/dev
```

YAML checker script bugs (my script, not the project):

| # | Issue | Fix |
|---|-------|-----|
| 16 | `yaml.load` choked on multi-doc files (`---` separators) | `yaml.load_all` |
| 17 | Skeleton `ci.yaml` contains `{{% raw %}}` — not valid YAML pre-render | Exclude `templates/` from sweep; check rendered output instead |
| 18 | `kubectl kustomize deploy/overlays/dev` — path doesn't exist at repo root | Deploy dirs live in the skeleton/render output → use `render-output/payments-api/deploy/overlays/dev` |

---

## Phase 4 — Docker verification (daemon came up)

```bash
docker build -t payments-api:verify .     # rendered repo; multi-stage, npm ci
docker run -d --name idp-verify -p 18080:8080 payments-api:verify
curl -fsS http://127.0.0.1:18080/health   # {"status":"ok","service":"payments-api"}
curl -fsS http://127.0.0.1:18080/metrics  # Prometheus output
docker exec idp-verify id -un             # app (non-root)
docker inspect -f '{{.State.Health.Status}}' idp-verify
docker rm -f idp-verify && docker rmi payments-api:verify
```

Result: build + runtime + healthcheck + non-root all verified.
README §7 limitation downgraded; §6 results table gained a row.

---

## Phase 5 — Polish (lockfile, SHA pins, git)

### 5a. Skeleton `package-lock.json` (for `npm ci` + cache)

```bash
TMP=$(mktemp -d)
# package.json with ${{ values.* }} swapped for literals npm accepts
npm install --package-lock-only --no-audit --no-fund     # in $TMP
# restore "${{ values.service_name }}" into both lockfile name fields
# → templates/service-node/skeleton/package-lock.json (4,796 lines, lockfileVersion 3)
```

| # | Issue | Symptom | Fix |
|---|-------|---------|-----|
| 19 | Validation one-liner used `json.load(Path)` | `AttributeError: 'PosixPath' object has no attribute 'read'` | `json.loads(path.read_text())` |
| 20 | Lockfile name must match rendered package.json | npm ci would be out of sync | Kept the `${{ values.service_name }}` placeholder inside the lockfile so Backstage renders it (render test asserts both name fields) |

Then switched consumers to `npm ci`:

- CI: `npm install` → `npm ci`, `setup-node` gains `cache: npm`
- Dockerfile: explicit `COPY package.json package-lock.json` + `RUN npm ci --omit=dev`
- README quick start: `npm install` → `npm ci` (both root and skeleton READMEs)

| # | Issue | Fix |
|---|-------|-----|
| 21 | README claimed `npm test` runs "lint → unit tests" but render test only rendered | Extended `render-test.mjs`: after render assertions, runs `npm ci` → `npm run lint` → `npm test` inside `render-output/` via `execSync` — claim is now true |
| 22 | Duplicate "render test passed" summary lines after extension | Removed intermediate log line |

### 5b. SHA-pinning actions

```bash
# per action, e.g.:
git ls-remote https://github.com/actions/checkout.git refs/tags/v7.0.1 'refs/tags/v7.0.1^{}'
```

All 5 actions rewritten as `uses: <owner>/<repo>@<40-char-commit-sha> # <tag>`
(zsh word-split issue #13 hit here too and was fixed the same way).

### 5c. Final verification

```bash
# render + install + lint + unit tests in one command:
npm test
# → lockfile install: OK / eslint on rendered output: OK /
#   unit tests on rendered output: OK /
#   render test passed: 19 files rendered, lint + unit tests green on output

npm run test:terraform
# → observability-baseline: 4 passed; service-baseline: 4 passed
```

### 5d. Git init + initial commit

```bash
# .gitignore created: node_modules/, render-output/, .terraform/, *.tfstate, .DS_Store
#   (lockfiles deliberately NOT ignored — committed for reproducibility)

git init -b main
git add -A
git status --short                        # 48 files staged
git grep -nIE '(ghp_|github_pat_|AKIA[0-9A-Z]{16}|BEGIN ...PRIVATE|sk-...)'
# → only hit: "ghp_xxx" placeholder in backstage/README.md (safe)

git commit -m "Initial commit: IDP golden-path starter (Backstage template, signed CI, Terraform modules, GitOps, CEL policy)"
# → 075fc1d, 48 files, 6,691 insertions, working tree clean
```

| # | Issue | Resolution |
|---|-------|------------|
| 23 | Secret scan flagged `ghp_xxx` | Placeholder in docs, not a real token — no action |

---

## Phase 6 — Live demo (real Backstage + real GitHub CI)

Everything above passes offline. Phase 6 proves the golden path end to end against live
systems: a real Backstage instance, a real GitHub repo, a real signed image.

```bash
# Backstage app (create-app rejected Node 25 as non-LTS; Node 24 via homebrew path)
export PATH="/opt/homebrew/opt/node@24/bin:$PATH"
npx @backstage/create-app@latest --path backstage-app   # --path IS the app dir
# guest auth, template locations (file: template.yaml + org.yaml), merged into app-config.yaml

# Split dev processes (see issue 25 — do NOT use `yarn start`):
yarn workspace backend start     # :7007
yarn workspace app start         # :3000 (proxies /api → :7007)

# Real demo repo rendered from the template and pushed:
gh repo create OtowoSamuel/payments-api --public
git push → run #1: lint-and-test 13s ✓, build-sign-push 44s ✓ (cosign sign + verify), 1m 4s total

# Independent supply-chain receipt (outside CI):
cosign verify ghcr.io/otowosamuel/payments-api@sha256:db872661… \
  --certificate-identity-regexp "https://github.com/OtowoSamuel/payments-api/" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
# → cosign claims validated, transparency log verified, certificate verified

# Screenshots (Playwright, deviceScaleFactor=2) → docs/assets/screenshots/:
#   backstage-create / backstage-form / backstage-catalog / github-repo /
#   github-actions-run / service-health
```

| # | Issue | Resolution |
|---|-------|------------|
| 24 | `yarn install` failed 4× with `ENOENT: … got-npm-11.8.2-c1eb105458.patch` | Not a network problem: `@backstage-cli-module-package-manager-yarn` depends on `@yarnpkg/core@^4.9.1`, and the freshly published **4.9.2 has a broken manifest** — it declares `"got": "patch:…#~/.yarn/patches/…"` pointing into Yarn's own repo. Pin it in root `package.json`: `"resolutions": { "@yarnpkg/core": "npm:4.9.1" }`. Install went 6.5 min-to-fail → **4m05s green**. |
| 25 | Backend died at boot: `IPC request 'DevDataStore.load' … timed out` for all 13 plugins | `yarn start` (`repo start`) runs webpack-dev-server **and** the IPC parent in one process; the first frontend compile starves the event loop past the 5s IPC deadline. Fix: run `yarn workspace backend start` and `yarn workspace app start` as separate processes. |
| 26 | Scaffolder page crashed: `Missing required config value at 'app.support.items'` | Two facts stacked: (a) if `app.support` exists, `items` is **required** (`useSupportConfig`), and (b) the config injected into the frontend **silently drops empty arrays** — `items: []` never arrives. Fix: ship one real support item. |
| 27 | Catalog rejected the rendered entity: `"annotations.backstage.io/kubernetes/id-selector" is not valid` | The template invented an annotation (`backstage.io/kubernetes/id-selector`) that doesn't exist in the catalog schema. Standard key is `backstage.io/kubernetes-id`. Fixed in skeleton + rendered output + pushed to the demo repo (commit `77c953a`). Exactly the "verify against the current release, not your memory" lesson, again. |
| 28 | URL location refused: `Reading from 'https://raw.githubusercontent.com/…' is not allowed` | Two missing pieces: `integrations.github.token: ${GITHUB_TOKEN}` had no env var in the dev shell (2nd redacted secret appears once exported), and the generic fetch reader needs an explicit allow list: `backend.reading.allow: [{ host: raw.githubusercontent.com }]`. |
| 29 | Group entities failed validation: `/spec must have required property 'children'` | Backstage requires `spec.children` on every Group. Added `children: []` (and the real hierarchy under `everyone`). |
| 30 | Fix pushed but backend kept ingesting the old annotation | GitHub raw CDN edges disagreed for ~2 minutes. Verified with Node `fetch` (the backend's own stack) until 4/4 returned the fixed file, then restarted the backend. |
| 31 | Screenshot script 404'd on `/catalog` | The app config remaps the catalog route to `/` (create-app default). Script navigates to `/` and waits for `All Components`. |

---

## Phase 7 — Live on AWS (EKS `golden-path-demo`)

The whole path became real in this phase. Up to Phase 6 everything was real CI on real GitHub, but the cluster side was just manifests. Phase 7 deployed everything onto a real EKS cluster in the author's account (`050083686295`, us-east-1) — Argo CD v3.2.1, Kyverno v1.19.1, both Terraform modules applied for real, and the generated `payments-api` running behind an AWS LoadBalancer. It also found six more issues — half of them invisible to every test in the repo, because mocks and kustomize renders don't talk to AWS or Kubernetes admission.

**What we found:**

- **ECR lifecycle priority** (issue 32): `tagStatus: any` must carry the highest priority number per storage class. Mock-provider tests can't see this — they never call `PutLifecyclePolicy`. Swapped the rule order in `service-baseline`. Real-AWS validation > mock coverage.

- **Our own policy blocked our template** (issue 33): The policy checks `object.metadata.labels` on the Deployment; the skeleton only put `team` on the pod template labels. The policy file even claimed generated services "pass automatically" — they didn't. Fixed the skeleton (team on Deployment metadata) and pushed to the demo repo. Governance‑by‑construction: the platform blocked its own non-compliant output until the template was honest.

- **GHCR requires lowercase** (issue 34): Image names must be all‑lowercase; the template rendered the GitHub login verbatim while CI lowercases the actual push (`${GITHUB_REPOSITORY,,}`). Skeleton now pipes owner/repo through nunjucks `| lower`.

- **`runAsNonRoot` with named `USER app`** (issue 35): kubelet can't prove a named `USER app` is non‑root. Added `runAsUser/runAsGroup: 10001` to the pod securityContext (image keeps its named user for humans).

- **Argo CD `install.yaml` had no Namespace** (issue 36): The common bundle ships no `kind: Namespace` resource — resources landed in `default`. Deleted by manifest identity, created `argocd` ns, re‑applied with `kubectl apply -n argocd -f`. Rule of thumb: audit third‑party bundles for `kind: Namespace` before applying.

- **Kyverno install CRD annotation overflow** (issue 37): The client‑side‑apply limit of 262144 bytes on `last-applied-configuration` annotation overflows on large CRDs. Fix (documented upstream): `kubectl apply --server-side -f …`.

**Proof points captured** (all in `docs/assets/screenshots/live/`, 2× resolution):

- public `/health` on the ELB → `{"status":"ok"}`
- Argo CD UI showing `payments-api-dev` **Synced + Healthy** against `github.com/OtowoSamuel/payments-api`
- Kyverno deny + allow side‑by‑side
- Real ECR repo / log group / 5xx alarm from `terraform apply`
- cluster runtime with the deployed image digest
- fresh Backstage create + catalog

All four demo‑repo commits from this phase (team label, lowercase image, numeric runAsUser, LoadBalancer) went through the golden‑path CI green — including cosign sign — before Argo was allowed to converge.

One nuance: the deny proof must use a **Deployment**, not `kubectl run` — the policy matches controllers (`deployments/statefulsets/daemonsets`), and a bare Pod sails through. Bare pods bypassing controller policies is exactly why platforms also schedule everything via Deployments.

---

## Final state

What’s in the repo at this point:

- `npm test` (render → npm ci → lint → unit tests): 19 files, all green
- `npm run test:terraform` (mock provider, no creds): 8/8 passing
- `kubectl kustomize render-output/.../deploy/overlays/dev` builds
- YAML duplicate‑key sweep (project + rendered): 21 docs clean
- Docker build + run: `/health` 200, non‑root `app`, HEALTHCHECK works
- Git: `main`, clean tree (history in GitHub)
- Dependency currency: audited vs Oct 5, 2026 releases; Actions SHA‑pinned
- Live GitHub CI (demo repo `OtowoSamuel/payments-api`): 6 green runs total (initial path + kubernetes‑id fix + 4 Phase‑7 fixes: lint → test → build → cosign sign+verify)
- `cosign verify` from a laptop (outside CI): claims + transparency log + certificate all verified
- Backstage live (guest auth, template registered): Create form renders, catalog ingests the generated `payments-api` with owner/system
- Article screenshots (2×): 6 in `docs/assets/screenshots/`, 8 more in `.../live/`, all content‑verified
- E2E live on AWS: EKS `golden-path-demo` (k8s 1.34, 2× t3.medium) + Argo CD v3.2.1 + Kyverno v1.19.1; app **Synced+Healthy**; public ELB `/health` → `{"status":"ok"}`
- Terraform applied for real: ECR `payments-api` (IMMUTABLE, scan‑on‑push), log group `/service/payments-api/dev`, alarm `payments-api-dev‑http‑5xx` (OK)
- Kyverno admission, proven live: unlabeled Deployment **denied**; labeled Deployment admitted; generated service passes after issue‑33 fix

- No CI workflow in *this* repo yet (Docker verified locally instead)
- Second template (Python), `ImageValidatingPolicy`, GitHub auth:
  deliberate scope cuts — rationale in `docs/decision-log.md` §8

---

## Phase 8 — Live testing & auto-discovery

Real user testing on the live stack surfaced three more issues, all invisible to the repo's tests because they only appear when Backstage, GitHub, and Argo CD interact for real.

### Issue 38 — Kyverno blocked the Argo CD upgrade

Upgrading Argo CD v3.2.1 → v3.5.4 failed: our own `kyverno-require-labels.yaml` policy denied the argocd namespace pods (they lack the required labels). Fixed by adding `matchConditions` namespace exemptions for `argocd`, `kyverno`, and `kube-system` — platform infrastructure shouldn't be blocked by its own admission policy.

### Issue 39 — `allowedHosts` rejected by current scaffolder

The `publish:github` action input `allowedHosts: ['github.com']` caused a validation error with the current `@backstage/plugin-scaffolder-backend`. The field only belongs on the `RepoUrlPicker` UI component (line 51), not the action input. Removed from the publish step.

### Issue 40 — No auto-discovery: every service needed a manual `kubectl apply`

Initially, each scaffolded service required manually applying its `deploy/argocd/application-dev.yaml` to the cluster. The skeleton still ships this file (useful for standalone use), but the live cluster now uses an **ApplicationSet** instead.

**What was tried:**

1. **`scmProvider.github` generator** — failed with 404 because `OtowoSamuel` is a user account, not a GitHub org. The generator hardcodes `/orgs/<org>/repos`; user accounts need `/users/<user>/repos`. No `user` field exists in the CRD.

2. **`git` generator** (chosen) — watches `services/*` directories in this repo. Each directory name maps to `github.com/OtowoSamuel/<name>`. Works with any account type. The `services/<name>/` directory needs at least one real file (not just `.gitkeep`) for the generator to detect it.

**How onboarding works now:**

```bash
# After scaffolding via Backstage (repo gets 'golden-path' topic automatically):
mkdir -p services/<name>
echo "repo: <name>" > services/<name>/service.yaml
git add services/ && git commit -m "Register <name>" && git push
# Argo CD discovers it within ~3 minutes
```

The `addTopics: golden-path` input on `publish:github` tags new repos automatically. The topic isn't strictly required by the git generator (it uses directory names), but it's good hygiene and enables future scmProvider use if the account converts to an org.

### Issue 41 — Repo-server cache held stale directory list

After pushing the `services/` directories, the git generator still reported "generated 0 applications". The argocd-repo-server caches git clones; deleting the pod (`kubectl delete pod -l app.kubernetes.io/name=argocd-repo-server`) forced a fresh clone and the generator picked up the directories immediately.

### User-error note — wrong owner cascades

Typing `Otowo` instead of `OtowoSamuel` during scaffolding propagated through the template: the GitHub repo, the GHCR image path (`ghcr.io/otowo/test-service`), and the Argo CD Application repoURL all pointed at the wrong account. The `OwnerPicker` UI field pulls from the catalog, but the `repoUrl` parameter's owner is free-text from the `RepoUrlPicker` — users can still mistype it. Not a template bug, but worth documenting.
