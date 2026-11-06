variable "name" {
  description = "The domain's DNS name, such as ad.example.internal."
  type        = string

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$", var.name))
    error_message = "name is the domain's DNS name, such as ad.example.internal."
  }
}

variable "short_name" {
  description = "The domain's NetBIOS name, such as CORP."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9-]{0,14}$", var.short_name))
    error_message = "short_name is up to 15 letters, digits and hyphens."
  }
}

variable "edition" {
  description = "Standard or Enterprise. Only Enterprise can be extended to another region."
  type        = string

  validation {
    condition     = contains(["Standard", "Enterprise"], var.edition)
    error_message = "edition is Standard or Enterprise."
  }
}

variable "description" {
  description = "What the directory is for."
  type        = string
  default     = ""
}

variable "vpc_id" {
  description = "The VPC holding the domain controllers: the primary hub's egress VPC."
  type        = string
}

variable "subnet_ids" {
  description = "Two subnets in different zones for the two domain controllers: the hub's dns tier."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) == 2
    error_message = "subnet_ids is two subnets, in two zones."
  }
}
