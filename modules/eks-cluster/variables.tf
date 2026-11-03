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

variable "admins" {
  description = "IAM role ARNs given cluster-wide admin access (AmazonEKSClusterAdminPolicy)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.admins : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", arn))])
    error_message = "admins are IAM role ARNs, such as arn:aws:iam::111111111111:role/platform-admin."
  }
}

variable "viewers" {
  description = "IAM role ARNs given cluster-wide read-only access (AmazonEKSViewPolicy), which does not include reading secrets."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.viewers : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", arn))])
    error_message = "viewers are IAM role ARNs, such as arn:aws:iam::111111111111:role/developer."
  }

  validation {
    condition     = length(setintersection(toset(var.admins), toset(var.viewers))) == 0
    error_message = "A role is an admin or a viewer, not both."
  }
}

variable "public_access_cidrs" {
  description = "Addresses that may reach the Kubernetes API from the internet. Empty (the default) keeps the API private: reachable only from inside the network."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.public_access_cidrs : can(cidrnetmask(c)) && c != "0.0.0.0/0"])
    error_message = "public_access_cidrs are CIDRs such as 203.0.113.10/32, and never 0.0.0.0/0."
  }
}

variable "deletion_protection" {
  description = "Whether EKS refuses to delete the cluster. Set false only to take an environment down."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "How long the control plane's logs are kept."
  type        = number
  default     = 365
}
