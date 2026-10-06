mock_provider "aws" {}

run "creates_repository_with_correct_name" {
  command = plan

  variables {
    service_name = "payments-api"
    team         = "payments"
  }

  assert {
    condition     = aws_ecr_repository.this.name == "payments-api"
    error_message = "ECR repository must be named after the service"
  }

  assert {
    condition     = aws_ecr_repository.this.image_tag_mutability == "IMMUTABLE"
    error_message = "Repositories must be immutable by default (supply-chain safety)"
  }

  assert {
    condition     = aws_ecr_repository.this.image_scanning_configuration[0].scan_on_push == true
    error_message = "Scan-on-push must be enabled by default"
  }
}

run "rejects_invalid_service_name" {
  command = plan

  variables {
    service_name = "Invalid_Name"
    team         = "payments"
  }

  expect_failures = [var.service_name]
}

run "mutable_override_for_dev" {
  command = plan

  variables {
    service_name         = "payments-api"
    team                 = "payments"
    image_tag_mutability = "MUTABLE"
  }

  assert {
    condition     = aws_ecr_repository.this.image_tag_mutability == "MUTABLE"
    error_message = "image_tag_mutability override must be respected"
  }
}

run "tags_include_ownership" {
  command = plan

  variables {
    service_name = "payments-api"
    team         = "payments"
    environment  = "prod"
  }

  assert {
    condition     = aws_ecr_repository.this.tags["Team"] == "payments"
    error_message = "Every resource must carry a Team tag for ownership"
  }

  assert {
    condition     = aws_ecr_repository.this.tags["Environment"] == "prod"
    error_message = "Every resource must carry an Environment tag"
  }
}
