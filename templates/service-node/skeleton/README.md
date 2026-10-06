# ${{ values.service_name }}

${{ values.description }}

Owned by **${{ values.owner }}**. Generated from the `service-node` golden-path template.

## Endpoints

| Path      | Purpose                    |
|-----------|----------------------------|
| `/health` | Liveness probe             |
| `/ready`  | Readiness probe            |
| `/metrics`| Prometheus metrics         |
| `/api/hello` | Demo application route  |

## Development

```bash
npm ci
npm run lint
npm test
npm run dev
```

## Observability

- **Metrics**: Prometheus scrapes `/metrics` (annotation-driven discovery).
- **Traces**: OpenTelemetry SDK is initialized at startup. Set
  `OTEL_EXPORTER_OTLP_ENDPOINT` to enable export; otherwise tracing stays dormant.
  Auto-instrumentation covers Express and HTTP out of the box.

## Delivery

- CI (`.github/workflows/ci.yaml`): lint → test → build → **Cosign keyless sign** → push to GHCR.
- GitOps: Argo CD `Application` lives in `deploy/argocd/`. Apply it once (or
  reference it from an app-of-apps repo); Argo then syncs `deploy/overlays/dev`.
- Images are signed at push time — admission controllers can verify with
  `cosign verify` before scheduling pods.

## Catalog

`catalog-info.yaml` registers this repo in the developer portal with owner,
pipeline link, and repository link.
