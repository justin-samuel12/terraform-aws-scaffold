variable "name" {
  description = "The cluster's name: the environment it belongs to. Its roles and log group are named from it."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,31}$", var.name))
    error_message = "name is lowercase letters, digits and hyphens, 32 characters at most."
  }
}

variable "kubernetes_version" {
  description = "The Kubernetes version, such as 1.34. Chosen on purpose, never guessed: EKS lists the versions it offers with aws eks describe-cluster-versions."
  type        = string

  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.kubernetes_version))
    error_message = "kubernetes_version is a version EKS offers, written like 1.34."
  }
}

variable "subnet_ids" {
  description = "The private subnets, one per zone, the control plane's network interfaces and the nodes go in."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "EKS needs subnets in at least two availability zones."
  }
}

variable "security_group_ids" {
  description = "Extra security groups on the control plane's network interfaces, such as one letting people's kubectl reach it on 443. EKS adds its own cluster security group either way."
  type        = list(string)
  default     = []
}

variable "kms_key_arn" {
  description = "The environment's data key, encrypting Kubernetes secrets."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:", var.kms_key_arn))
    error_message = "kms_key_arn is a KMS key's ARN."
  }
}

variable "access_entries" {
  description = "Who may use the cluster, as aws_eks_access_entry and aws_eks_access_policy_association take it: each an IAM role's ARN (principal_arn) and the EKS access policies it gets, each with its access_scope (type cluster, or namespace with namespaces)."
  type = list(object({
    principal_arn = string
    access_policy_associations = list(object({
      policy_arn = string
      access_scope = object({
        type       = string
        namespaces = optional(list(string), [])
      })
    }))
  }))
  default = []

  validation {
    condition     = alltrue([for e in var.access_entries : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", e.principal_arn))])
    error_message = "principal_arn is an IAM role's ARN, such as arn:aws:iam::111111111111:role/platform-admin."
  }

  validation {
    condition     = length(distinct([for e in var.access_entries : e.principal_arn])) == length(var.access_entries)
    error_message = "A role has one access entry, holding every policy it gets."
  }

  validation {
    condition = alltrue(flatten([for e in var.access_entries : [
      for a in e.access_policy_associations : can(regex("^arn:aws[a-z-]*:eks::aws:cluster-access-policy/[A-Za-z]+$", a.policy_arn)) && ((a.access_scope.type == "cluster" && length(a.access_scope.namespaces) == 0) || (a.access_scope.type == "namespace" && length(a.access_scope.namespaces) > 0))
    ]]))
    error_message = "policy_arn is an EKS access policy's ARN, and access_scope is type cluster, or type namespace with namespaces."
  }
}

variable "endpoint_public_access" {
  description = "Whether the Kubernetes API is reachable from the internet, from public_access_cidrs only. The private endpoint is always on."
  type        = bool
}

variable "public_access_cidrs" {
  description = "Addresses that may reach the Kubernetes API from the internet, when endpoint_public_access is true."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.public_access_cidrs : can(cidrnetmask(c)) && c != "0.0.0.0/0"])
    error_message = "public_access_cidrs are CIDRs such as 203.0.113.10/32, and never 0.0.0.0/0."
  }

  validation {
    condition     = var.endpoint_public_access == (length(var.public_access_cidrs) > 0)
    error_message = "public_access_cidrs are set exactly when endpoint_public_access is true."
  }
}

variable "deletion_protection" {
  description = "Whether EKS refuses to delete the cluster."
  type        = bool
}

variable "log_retention_days" {
  description = "How long the control plane's logs are kept."
  type        = number
  default     = 365
}

variable "role_boundary" {
  description = "Where every IAM role, instance profile and policy this module creates goes, and the permission boundary each role carries: the deploying duty's, so a role can never do more than the pipeline lets that duty do. null: path / and no boundary."
  type = object({
    path                 = string
    permissions_boundary = string
  })
  default = null
}
