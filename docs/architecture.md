# Architecture

```mermaid
flowchart LR
    subgraph platform["Developer Machine + GitHub"]
        subgraph portal["Developer Portal"]
            dev[Developer] --> ui[Backstage UI]
            ui -->|"Create service form"| tpl["Software Template<br/>service-node/template.yaml"]
            tpl -->|"register"| cat[Software Catalog<br/>owner · links · lifecycle]
        end

        subgraph cicd["CI/CD"]
            tpl -->|"1. render"| ws[(Workspace)]
            tpl -->|"2. publish"| gh[GitHub repo<br/>CI + Dockerfile + kustomize + catalog-info]
            gh -->|"push to main"| ci["GitHub Actions<br/>lint → test → build → cosign sign → push"]
            ci -->|image| ghcr[(GHCR<br/>signed)]
        end
    end

    subgraph aws["AWS Account"]
        subgraph runtime["Runtime"]
            gh -->|manifests| gitops[GitOps folder<br/>deploy/overlays/dev]
            gitops --> argo[Argo CD Application]
            argo -->|"sync"| k8s[(Kubernetes)]
            ghcr -->|"pulls image"| k8s
            k8s --> pod[App Pod]
        end

        subgraph controls["Controls"]
            kyverno["Kyverno ValidatingPolicy<br/>labels enforced"] -.->|validation| pod
            pod -.->|"scrape /metrics"| prom["Prometheus metrics<br/>(wiring only)"]
            pod -.->|"OTLP traces"| otel["OTel hooks<br/>(dormant by default)"]
        end

        subgraph observability["Observability"]
            tf1["Terraform<br/>service-baseline"] -.-> ghcr
            tf2["Terraform<br/>observability-baseline"] -.->|"log group + 5xx alarm"| cw["CloudWatch"]
        end
    end
```

## Component responsibilities

| Component | Responsibility | Where it lives |
|---|---|---|
| Backstage | Self-service form + catalog | `backstage/` (run as separate app) |
| Software Template | Renders and publishes the golden path | `templates/service-node/` |
| Skeleton | The approved repo structure | `templates/service-node/skeleton/` |
| GitHub Actions | lint, test, build, **Cosign sign**, push | in the skeleton, `.github/workflows/ci.yaml` |
| Argo CD | Applies manifests from the generated repo | in the skeleton, `deploy/argocd/` |
| Terraform | Per-service cloud resources (ECR, logs, alarms) | `terraform-modules/` |
| Kyverno | Admission gate: labels must exist | `policies/` |

## The key design choice

The template does **not** call Terraform or Argo directly. It generates a
repo whose structure *is* the golden path — the CI workflow, the manifests,
the catalog file. Existing machinery (GitHub, Argo) then works on it with
zero extra wiring. Governance by construction: services created outside
the template are the exception, and Kyverno is the backstop.

## Runtime visibility (wiring, not running)

The skeleton ships **Prometheus annotations** and **OpenTelemetry hooks**
from line one — but no collector is deployed by default. The `/metrics`
endpoint responds, the OTel SDK activates only when
`OTEL_EXPORTER_OTLP_ENDPOINT` is set. Plugging in a real Prometheus or
OTel collector later means setting an environment variable, not rewriting
the service.
