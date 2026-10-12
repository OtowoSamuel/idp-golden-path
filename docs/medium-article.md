**Nobody Follows the Onboarding Doc. So I Turned It Into a Portal Click.**

*Building an Internal Developer Platform starter with Backstage, keyless Cosign signing, Argo CD, and Kyverno: five design decisions, five bugs, and an honest list of what it doesn't do yet.*

<!--
PUBLISHING CHECKLIST (Medium doesn't import local images — upload manually):
1. Cover image: assets/cover.png
2. assets/architecture.png → after "The stack:" line
3. assets/screenshots/live/live-health-url.png → "Proof it runs" section
4. assets/screenshots/live/live-argo-app.png → "Proof it runs" section
5. assets/screenshots/live/live-cluster-runtime.png → "Proof it runs" section
6. assets/screenshots/live/live-aws-resources.png → "Proof it runs" section
7. assets/screenshots/live/live-backstage-create.png → Decision 1
8. assets/screenshots/live/live-backstage-form.png → Decision 1
9. assets/screenshots/live/live-backstage-catalog.png → Decision 1 (catalog)
10. assets/screenshots/live/live-kyverno-deny.png → Decision 4 (denied)
11. assets/screenshots/live/live-kyverno-allow.png → Decision 4 (admitted)
12. assets/screenshots/live/live-cloudwatch-overview.png → Decision 5
13. assets/screenshots/service-health.png → Decision 5 (fresh clone)
14. assets/screenshots/github-repo.png → Results
15. assets/screenshots/github-actions-run.png → Results
-->

Every platform team eventually writes the same document: create a repo, add a Dockerfile, wire up CI, add these labels… And every new service quietly skips half of it.

That's copy-paste drift, the tech debt no tracker shows. A team clones an old service to start a new one, inherits a deprecated CI action, keeps a Dockerfile from three Node versions ago, and drops the labels the policy engine requires. Six months later, nobody can say which services are compliant and which are archaeology.

More documentation won't fix that. A golden path will: a self-service template that generates repos which are correct by construction.

So I built one. From three fields in a portal form, a developer gets:

- A GitHub repo with CI that lints, tests, builds, and keyless-signs the container image
- Kubernetes manifests that Argo CD syncs automatically
- The labels the admission policy demands, already in place
- OpenTelemetry and Prometheus hooks that work on first boot
- A catalog entry with an owner, a system, and a lifecycle

Below: the architecture, the five decisions that shaped it, the five bugs that taught me the most, and what it doesn't do yet.

## The flow, in one line

```
Developer → Backstage form → template renders golden-path repo →
CI signs the image → Argo CD syncs manifests → catalog shows ownership
```

**The stack:** Backstage (Software Templates v1beta3), GitHub Actions with Cosign keyless signing, Terraform modules for baseline infrastructure, Argo CD for GitOps, Kyverno for admission policy, and OpenTelemetry plumbed in from line one.

## Proof it runs

A diagram proves nothing, so here is the deployed version.

The generated service answers on a public load balancer:

<!-- INSERT assets/screenshots/live/live-health-url.png -->

Argo CD reports it Synced and Healthy:

<!-- INSERT assets/screenshots/live/live-argo-app.png -->

The cluster is running the image CI built and signed:

<!-- INSERT assets/screenshots/live/live-cluster-runtime.png -->

And Terraform created the AWS side (an ECR repository, a log group, and a 5xx alarm) without anyone clicking through a console:

<!-- INSERT assets/screenshots/live/live-aws-resources.png -->

## Decision 1: The template generates a repo, not infrastructure

The scaffolder does three things: renders files, pushes a repo, registers the catalog entry. No `terraform apply` at click time, no cluster calls.

The developer's side of the click. First, pick the golden path:

<!-- INSERT assets/screenshots/live/live-backstage-create.png -->

Then fill in three fields: service name, description, owner. The repo, the CI, and the manifests come for free.

<!-- INSERT assets/screenshots/live/live-backstage-form.png -->

**Why this works:** every external call is a way for the template to fail for reasons unrelated to the developer's request. And the generated repo is inspectable: a reviewer opens GitHub and sees exactly what the platform approved.

The trade-off: provisioning happens on the first pipeline run instead of instantly. For a starter, a working, signed repo in under 15 minutes beats half-provisioned infrastructure.

The last step registers the service in the catalog, with ownership rendered by the template and never hand-written, because an unowned service is an unmanaged service:

<!-- INSERT assets/screenshots/live/live-backstage-catalog.png -->

## Decision 2: Sign images keyless, or not at all

The number one reason teams skip image signing is key management. So the CI uses Cosign's keyless mode with GitHub OIDC: no key material anywhere in the repo, and verification is tied to the exact repository and workflow identity.

```yaml
- run: cosign sign --yes "${{ steps.image.outputs.name }}@${{ steps.build.outputs.digest }}"
- run: |
    cosign verify ... \
      --certificate-identity-regexp "https://github.com/${GITHUB_REPOSITORY}/" \
      --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

All five Actions in the pipeline are SHA-pinned to their release commits. A pipeline that verifies everything else shouldn't float on mutable tags itself.

One honest note: the signature is verified inside the pipeline. Enforcing it at cluster admission is the next step (see *What it doesn't do yet*).

## Decision 3: Tests that need zero cloud credentials

This is the decision I'd defend hardest. The Terraform modules use `mock_provider "aws"`, and a Node render test scaffolds the template offline, then runs the generated repo's lint and unit tests against the output.

**Why:** a portfolio project gets judged by whoever clones it, possibly with no AWS account, possibly on a plane. Tests that need credentials don't get run. Both suites finish in seconds, offline.

## Decision 4: One policy, not a policy library

The Kyverno policy requires two labels (`app.kubernetes.io/name` and `team`) on every workload. Generated services carry them automatically, so the policy exists to stop hand-made services from reaching the cluster unowned.

One policy proves the compliance loop. Thirty policies become the project.

It's written as a Kubernetes-native CEL `ValidatingPolicy` (more on why in bug #1). Here is the loop working. A Deployment without the labels is denied:

<!-- INSERT assets/screenshots/live/live-kyverno-deny.png -->

The same Deployment with the labels is admitted:

<!-- INSERT assets/screenshots/live/live-kyverno-allow.png -->

## Decision 5: Observability that starts on first run

The OpenTelemetry SDK initializes only if `OTEL_EXPORTER_OTLP_ENDPOINT` is set. Otherwise it logs "tracing disabled" and the server runs. A generated service must start with zero external dependencies.

The wiring, labels, and Prometheus annotations are all there. The hook exists; you plug in the collector when you have one. Plugging in a real one later means setting one environment variable, not rewriting the service.

The Terraform `observability-baseline` module provisions the CloudWatch side: a log group (`/service/<name>/<env>`) and a 5xx alarm on the load balancer. Both are created per service, tagged, and ready before the first pod starts.

The alarm watches `HTTPCode_Target_5XX_Count`, threshold 10, over two 5-minute periods. It's the cheapest possible safety net: no custom metrics, no agent, just the one number that means "something is broken."

<!-- INSERT assets/screenshots/live/live-cloudwatch-overview.png -->

And on a fresh clone, with no collector at all, the generated service still comes up healthy:

<!-- INSERT assets/screenshots/service-health.png -->

## The five bugs worth writing down

**1. Deprecated APIs don't announce themselves politely.** I first wrote the admission policy as a Kyverno `ClusterPolicy`. Then I checked the docs properly: deprecated in v1.19 (August 2026), removed in v1.20. Shipping it would have meant a policy that silently stops working within one release cycle. The lesson: verify your "standard" patterns against the current release, not your memory.

**2. Invented config keys fail late.** My Backstage guest-auth config used `enabled: true` and `allowOutsideOfVisitor`. Neither exists. The real API is `guest: {}`, with an ominously named `dangerouslyAllowOutsideDevelopment` escape hatch. Reading the provider's `config.d.ts` took 30 seconds and saved a broken startup.

**3. zsh doesn't word-split like bash.** A loop fetching Action SHAs with `set -- $spec` passed the whole string as one argument:

```
fatal: unable to access 'https://github.com/actions/checkout v7.0.1.git/': URL rejected: Malformed input
```

The fix, explicit parameter expansion (`repo="${spec%% *}"`), is elementary. The lesson is better: my test command and my shell disagreed, and the error pointed at git, not at me.

**4. The test claimed more than it ran.** My README said `npm test` "renders template → lint → unit tests." It rendered. That's all. A claim in a README is a contract with whoever clones the repo, so I made the test actually run `npm ci`, lint, and unit tests on the rendered output.

**5. A lockfile with a template variable inside it.** For `npm ci` to work in generated repos, the skeleton ships a `package-lock.json` whose `name` field contains `${{ values.service_name }}`. Generating it meant swapping placeholders for literals, running `npm install --package-lock-only`, then swapping them back, and asserting after every render that both name fields resolved correctly.

## The results

| Metric | Value |
|---|---|
| Portal click → green pipeline | **~2 minutes** (30s scaffold + 1m 4s CI) |
| Generated services with keyless Cosign signing | **100%** — it lives in the template |
| Generated services with catalog ownership | **100%** — rendered, never hand-written |
| Reusable Terraform modules (tested, mocked) | **2**, 8/8 tests passing |
| Credentials needed to run every test | **0** |
| Template render test | 19 files, lint + unit tests green on output |

The pipeline that ran on that push: lint and unit tests first, then build, Cosign keyless sign, and verify. 1m 4s end to end.

<!-- INSERT assets/screenshots/github-repo.png -->

<!-- INSERT assets/screenshots/github-actions-run.png -->

The repo ships its own receipts: an architecture diagram, a decision log (decision, why, trade-off), a full build log of every command and failure, and a rebuild guide so someone can reconstruct the whole thing from an empty folder.

## What it doesn't do yet

**Signatures are verified in CI, not at the cluster.** Kyverno enforces ownership labels but doesn't yet verify image signatures, so an unsigned image applied by hand could still be admitted. Next step: an image-verification policy pinned to the repo's workflow identity.

**One environment.** Only the `dev` overlay exists. Promotion path: add `overlays/staging/` and `overlays/prod/`, register via ApplicationSet. Kustomize already supports it.

**Runtime and cost.** 2× t3.medium = ~$0.22/hr (~$160/month). Scale-to-zero via `eksctl scale nodegroup --nodes 0`. Control plane stays at ~$0.10/hr.

**Backstage uses guest auth.** Real SSO is out of scope for a starter.

## Takeaways

**Golden paths beat guidelines.** A policy that has to be remembered will be forgotten; a template that's used can't be.

**Keyless signing removed the excuse.** Zero secrets, zero key management: the reason teams skip signing.

**Offline tests are a feature of the demo, not just the code.** Anyone who clones it gets green in under two minutes.

**Currency is maintenance.** Every pin (Actions, Node LTS, provider majors, policy APIs) was verified against October 2026 releases. A golden path with stale pins is self-defeating.

**Write the README first, then make it true.** Half my "bugs" were really gaps between what I claimed and what I ran.

---

If you run a platform team, I'd like to know what you would cut from this path, and what you'd add. Source, rebuild guide, and full build log: [github.com/OtowoSamuel/idp-golden-path](https://github.com/OtowoSamuel/idp-golden-path).
