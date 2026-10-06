# service-baseline

Creates the container registry foundation every generated service needs:
an ECR repository with scanning, encryption, immutable tags, and a lifecycle
policy that keeps costs bounded.

## Why this exists

When a developer creates a service from the portal, the image needs somewhere
to go. This module is the approved "somewhere" — no hand-rolled registries,
no missing scan-on-push, no unbounded storage growth.

## Usage

```hcl
module "payments_api" {
  source = "git::https://github.com/<you>/idp-golden-path.git//terraform-modules/service-baseline?ref=main"

  service_name = "payments-api"
  environment  = "dev"
  team         = "payments"
}
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `service_name` | `string` | — | ECR repo name (validated: `^[a-z][a-z0-9-]{2,39}$`) |
| `environment` | `string` | `"dev"` | `dev` \| `staging` \| `prod` |
| `team` | `string` | — | Ownership tag |
| `image_tag_mutability` | `string` | `"IMMUTABLE"` | `IMMUTABLE` prevents tag overwrite |
| `scan_on_push` | `bool` | `true` | ECR vulnerability scan per push |
| `keep_last_images` | `number` | `10` | Lifecycle retention for tagged images |
| `tags` | `map(string)` | `{}` | Extra tags |

## Outputs

| Name | Description |
|------|-------------|
| `repository_url` | Push target for CI (`registry/name`) |
| `repository_arn` | For IAM policy scoping |
| `registry_id` | Owning account ID |

## Tests

```bash
terraform init -backend=false
terraform test
```

Uses `mock_provider "aws"` — runs with **no AWS credentials**. 4 runs cover
naming, immutability, scanning, tag ownership, and input validation.
