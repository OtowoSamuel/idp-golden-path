# demo cluster stack

The EKS cluster the golden path runs on, built entirely with Terraform:
minimal public VPC + `terraform-aws-modules/eks/aws` v21 managed node group.

## Apply

```bash
terraform init
terraform apply                       # defaults: us-east-1, golden-path-demo, k8s 1.35
aws eks update-kubeconfig --name golden-path-demo
```

Then bootstrap the platform layer (see `docs/rebuild-guide.md` Step 11):
Argo CD, Kyverno + `policies/kyverno-require-labels.yaml`, and the
`demo-services` stack.

## Design notes

- **k8s 1.35, not the newest**: Kyverno 1.19 supports 1.33–1.35. Admission
  tooling is the constraint on upgrade velocity — not AWS's release page.
- **Public subnets only**: no NAT gateway (~$0/hr vs ~$32/mo). Nodes get
  public IPs; fine for a demo account, wrong for production (add private
  node subnets + NAT).
- **`enable_cluster_creator_admin_permissions`**: modern replacement for
  hand-editing `aws-auth` — the applying IAM identity gets cluster-admin
  via an EKS access entry.
- **State**: local for the demo; production would use an S3 backend with
  versioning + DynamoDB lock (see `docs/decision-log.md` §8).

## Teardown

```bash
terraform destroy
```
