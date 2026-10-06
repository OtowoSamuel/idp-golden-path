# Architecture

```mermaid
flowchart LR
    dev[Developer] --> ui[Backstage UI]
    ui -->|"Create service form"| tpl["Software Template<br/>service-node/template.yaml"]
    tpl -->|"1. render skeleton"| ws[(Workspace)]
    tpl -->|"2. publish"| gh[GitHub repo<br/>CI + Dockerfile + kustomize + catalog-info]
    tpl -->|"3. register"| cat[Software Catalog<br/>owner · links · lifecycle]
    gh -->|"push to main"| ci["GitHub Actions<br/>lint → test → build → cosign sign → push"]
    ci -->|image| ghcr[(GHCR<br/>signed)]
    ci -->|manifests live in repo| gitops[GitOps folder<br/>deploy/overlays/dev]
    gitops --> argo[Argo CD Application]
    argo -->|sync| k8s[(Kubernetes)]
    ghcr -->|image pulled| k8s
    k8s -->|scrape /metrics| prom[Prometheus]
    k8s -->|OTLP traces| otel[OTel Collector]
    kyverno[Kyverno policy<br/>labels enforced] -->|admission| k8s
    tf["Terraform modules<br/>service-baseline · observability-baseline"] -.->|provisioned per service| ghcr
    tf -.-> prom
```

## Component responsibilities

| Component | Responsibility | Where it lives |
|---|---|---|
| Backstage | Self-service form + catalog | `backstage/` (run as separate app) |
| Software Template | Renders and publishes the golden path | `templates/service-node/` |
| Skeleton | The approved repo structure | `templates/service-node/skeleton/` |
| GitHub Actions | lint, test, build, **Cosign sign**, push | in the skeleton, `.github/workflows/ci.yaml` |
| Argo CD | Applies manifests from the generated repo | in the skeleton, `deploy/argocd/` |
| Terraform | Per-service cloud resources (registry, logs, alarms) | `terraform-modules/` |
| Kyverno | Admission gate: labels must exist | `policies/` |

## The key design choice

The template does **not** call Terraform or Argo directly. It generates a
repo whose structure *is* the golden path — the CI workflow, the manifests,
the catalog file. Existing machinery (GitHub, Argo, Prometheus) then works
on it with zero extra wiring. Governance by construction: services created
outside the template are the exception, and Kyverno is the backstop.
