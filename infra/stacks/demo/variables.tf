variable "region" {
  description = "AWS region for the demo cluster"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "golden-path-demo"
}

variable "kubernetes_version" {
  description = <<-EOT
    Kubernetes version. 1.35 is the newest release Kyverno 1.19 supports
    (support matrix: 1.33–1.35) — pin to what your admission tooling can run,
    not blindly to the newest EKS version.
  EOT
  type        = string
  default     = "1.35"
}

variable "node_instance_types" {
  description = "Managed node group instance types"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired node count"
  type        = number
  default     = 2
}
