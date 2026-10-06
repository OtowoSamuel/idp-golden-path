# observability-baseline

Gives every generated service a logging destination and an alarm — the
minimum an operating service must have before traffic hits it.

## Why this exists

"The dashboard doesn't exist" is a common production surprise when services
are created by copy-paste. This module bakes in two defaults:

1. A CloudWatch Log Group with finite retention (cost control).
2. A 5xx alarm that can be disabled for dev but exists by design.

## Usage

```hcl
module "payments_api_observability" {
  source = "git::https://github.com/<you>/idp-golden-path.git//terraform-modules/observability-baseline?ref=main"

  service_name       = "payments-api"
  environment        = "dev"
  team               = "payments"
  alarm_enabled      = false   # dev: no alarm cost
  log_retention_days = 14
}
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `service_name` | `string` | — | Naming basis (validated pattern) |
| `environment` | `string` | `"dev"` | `dev` \| `staging` \| `prod` |
| `team` | `string` | — | Ownership tag |
| `log_retention_days` | `number` | `30` | Log retention (0 = never expire) |
| `alarm_enabled` | `bool` | `true` | Create the 5xx alarm |
| `alarm_5xx_threshold` | `number` | `10` | 5xx count / 5 min trigger |
| `alarm_topic_arn` | `string` | `null` | SNS topic for notifications |
| `tags` | `map(string)` | `{}` | Extra tags |

## Outputs

| Name | Description |
|------|-------------|
| `log_group_name` | Where service logs land |
| `log_group_arn` | For IAM / subscription filters |
| `alarm_arns` | Created alarm ARNs (may be empty) |

## Tests

```bash
terraform init -backend=false
terraform test
```

Uses `mock_provider "aws"` — runs with **no AWS credentials**. 4 runs cover
retention, alarm toggle, threshold propagation, and environment validation.
