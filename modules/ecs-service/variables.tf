variable "name" {
  description = "The application's name: its service, task definition family, log group and CodeDeploy application are <environment>-<name>."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,31}$", var.name))
    error_message = "name is lowercase letters, digits and hyphens, 32 characters at most."
  }
}

variable "environment" {
  description = "The environment it runs in."
  type        = string
}

variable "region" {
  description = "The region it runs in: its role names carry it, since roles are global."
  type        = string
}

variable "cluster" {
  description = "The environment's cluster, from the ecs-cluster module: its ARN and name."
  type = object({
    arn  = string
    name = string
  })
}

variable "execute_command" {
  description = "ECS Exec: the cluster's session log group and key, which the task role is allowed to use; null turns ECS Exec off for this service."
  type = object({
    log_group_arn = string
    kms_key_arn   = string
  })
  default = null
}

variable "cpu" {
  description = "CPU units for the whole task (1024 is one vCPU)."
  type        = number
  default     = 256

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096, 8192, 16384], var.cpu)
    error_message = "cpu is one of Fargate's sizes: 256, 512, 1024, 2048, 4096, 8192 or 16384."
  }
}

variable "memory" {
  description = "Memory in MiB for the whole task; Fargate allows a range for each cpu size."
  type        = number
  default     = 512

  validation {
    condition     = var.memory >= 512 && var.memory <= 122880 && var.memory % 512 == 0
    error_message = "memory is 512 to 122880 MiB in steps of 512; Fargate allows a range for each cpu size."
  }
}

variable "architecture" {
  description = "The CPU the containers are built for: X86_64 or ARM64 (Graviton, cheaper)."
  type        = string
  default     = "X86_64"

  validation {
    condition     = contains(["X86_64", "ARM64"], var.architecture)
    error_message = "architecture is X86_64 or ARM64."
  }
}

variable "containers" {
  description = "The task's containers: name, image, the port it listens on (the first with a port takes the load balancer's traffic), environment variables, secrets as name -> ARN, and an optional container health check."
  type = list(object({
    name        = string
    image       = string
    port        = optional(number)
    essential   = optional(bool, true)
    command     = optional(list(string))
    environment = optional(map(string), {})
    secrets     = optional(map(string), {})
    health_check = optional(object({
      command      = list(string)
      interval     = optional(number, 30)
      timeout      = optional(number, 5)
      retries      = optional(number, 3)
      start_period = optional(number, 0)
    }))
  }))

  validation {
    condition     = length(var.containers) > 0 && length(distinct([for c in var.containers : c.name])) == length(var.containers) && anytrue([for c in var.containers : c.essential]) && alltrue([for c in var.containers : can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", c.name)) && trimspace(c.image) != ""])
    error_message = "A task has at least one container, each with its own name and an image, and at least one essential."
  }

  validation {
    condition     = alltrue(flatten([for c in var.containers : [for k in keys(c.environment) : !can(regex("(?i)(password|secret|token|private_key|api_key|credential)", k))]]))
    error_message = "Environment variables never hold secrets: put them in Secrets Manager or Parameter Store and list them under secrets, name -> ARN (SKILLS.md)."
  }

  validation {
    condition     = alltrue(flatten([for c in var.containers : [for arn in values(c.secrets) : can(regex("^arn:aws[a-z-]*:(secretsmanager|ssm):[a-z0-9-]+:[0-9]{12}:(secret:|parameter/)", arn))]]))
    error_message = "secrets are name -> the full ARN of a Secrets Manager secret or a Parameter Store parameter."
  }
}

variable "desired_count" {
  description = "How many tasks run; with autoscaling, how many it starts with."
  type        = number
  default     = 2

  validation {
    condition     = var.desired_count >= 0 && floor(var.desired_count) == var.desired_count
    error_message = "desired_count is a whole number, 0 or more."
  }
}

variable "subnet_ids" {
  description = "The subnets the tasks run in: every zone of their tier."
  type        = list(string)
}

variable "security_group_ids" {
  description = "The security groups on every task's network interface."
  type        = list(string)

  validation {
    condition     = length(var.security_group_ids) > 0
    error_message = "A service needs at least one security group, so what may reach it is chosen."
  }
}

variable "vpc_id" {
  description = "The environment's VPC, for the target groups; needed only with routes."
  type        = string
  default     = null
}

variable "health" {
  description = "How the load balancer checks a task: path, healthy codes, interval and timeout in seconds, and checks in a row to be healthy or unhealthy."
  type = object({
    path                = optional(string, "/")
    matcher             = optional(string, "200-399")
    interval            = optional(number, 30)
    timeout             = optional(number, 5)
    healthy_threshold   = optional(number, 3)
    unhealthy_threshold = optional(number, 3)
  })
  default = {}
}

variable "routes" {
  description = "Where traffic reaches it: a shared listener (by ARN) and the hosts and paths it owns there, at a priority unique on that listener."
  type = list(object({
    listener_arn = string
    hosts        = optional(list(string), [])
    paths        = optional(list(string), [])
    priority     = number
  }))
  default = []

  validation {
    condition     = alltrue([for r in var.routes : length(r.hosts) + length(r.paths) > 0 && r.priority >= 1000 && r.priority <= 50000])
    error_message = "A route matches at least one host or path, with a priority from 1000 to 50000 (1 to 999 belong to the load balancer's own rules, so the two stacks never clash)."
  }

  validation {
    condition     = length(var.routes) == 0 || anytrue([for c in var.containers : c.port != null])
    error_message = "Routes need a container with a port to forward to."
  }
}

variable "load_balancer_arn_suffix" {
  description = "The routes' load balancer (app/<name>/<id>), for scaling on requests per task; null otherwise."
  type        = string
  default     = null
}

variable "autoscaling" {
  description = "Target tracking: between min_capacity and max_capacity tasks, keeping a metric (ECSServiceAverageCPUUtilization, ECSServiceAverageMemoryUtilization or ALBRequestCountPerTarget) near target_value. null: always desired_count."
  type = object({
    min_capacity           = number
    max_capacity           = number
    predefined_metric_type = optional(string, "ECSServiceAverageCPUUtilization")
    target_value           = number
  })
  default = null

  validation {
    condition     = var.autoscaling == null || try(var.autoscaling.min_capacity >= 0 && var.autoscaling.min_capacity <= var.autoscaling.max_capacity && contains(["ECSServiceAverageCPUUtilization", "ECSServiceAverageMemoryUtilization", "ALBRequestCountPerTarget"], var.autoscaling.predefined_metric_type), false)
    error_message = "autoscaling: min_capacity <= max_capacity, keeping ECSServiceAverageCPUUtilization, ECSServiceAverageMemoryUtilization or ALBRequestCountPerTarget near target_value."
  }

  validation {
    condition     = try(var.autoscaling.predefined_metric_type, "") != "ALBRequestCountPerTarget" || (length(var.routes) > 0 && var.load_balancer_arn_suffix != null && var.deployment.strategy == "rolling")
    error_message = "Scaling on requests per task needs routes and their load balancer, and a rolling deployment: blue/green swaps the target group it would count."
  }
}

variable "deployment" {
  description = "How a new version goes out. rolling: ECS replaces tasks a few at a time, rolling back by itself if they never become healthy. blue_green: CodeDeploy starts the new version beside the old and moves traffic all at once (CodeDeployDefault.ECSAllAtOnce), as a canary or linearly."
  type = object({
    strategy                         = optional(string, "rolling")
    deployment_config_name           = optional(string)
    minimum_healthy_percent          = optional(number, 100)
    maximum_percent                  = optional(number, 200)
    termination_wait_time_in_minutes = optional(number, 5)
    rollback_events                  = optional(list(string), ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_REQUEST"])
  })
  default = {}

  validation {
    condition     = contains(["rolling", "blue_green"], var.deployment.strategy)
    error_message = "deployment.strategy is rolling or blue_green."
  }

  validation {
    condition     = var.deployment.strategy == "blue_green" || var.deployment.deployment_config_name == null
    error_message = "A rolling deployment is ECS's own, so deployment_config_name (a CodeDeploy setting: all at once, canary or linear) needs strategy blue_green."
  }

  validation {
    condition     = var.deployment.deployment_config_name == null || (can(regex("^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$", coalesce(var.deployment.deployment_config_name, "-"))) && (!startswith(coalesce(var.deployment.deployment_config_name, "-"), "CodeDeployDefault.") || startswith(coalesce(var.deployment.deployment_config_name, "-"), "CodeDeployDefault.ECS")))
    error_message = "deployment_config_name is an ECS one, such as CodeDeployDefault.ECSAllAtOnce, CodeDeployDefault.ECSCanary10Percent5Minutes or CodeDeployDefault.ECSLinear10PercentEvery1Minutes, or a custom configuration's name."
  }

  validation {
    condition     = var.deployment.strategy == "rolling" || (length(var.routes) > 0 && var.codedeploy_role_arn != null)
    error_message = "A blue/green deployment moves traffic between two target groups, so it needs routes, and the environment's CodeDeploy role."
  }

  validation {
    condition     = var.deployment.termination_wait_time_in_minutes >= 0 && var.deployment.termination_wait_time_in_minutes <= 2880 && var.deployment.minimum_healthy_percent >= 0 && var.deployment.maximum_percent >= 100 && alltrue([for e in var.deployment.rollback_events : contains(["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM", "DEPLOYMENT_STOP_ON_REQUEST"], e)])
    error_message = "termination_wait_time_in_minutes is 0 to 2880, minimum_healthy_percent 0 or more, maximum_percent 100 or more; rollback_events are DEPLOYMENT_FAILURE, DEPLOYMENT_STOP_ON_ALARM or DEPLOYMENT_STOP_ON_REQUEST."
  }
}

variable "codedeploy_role_arn" {
  description = "The environment's CodeDeploy service role for ECS; needed only for blue_green."
  type        = string
  default     = null
}

variable "capacity_provider_strategy" {
  description = "How tasks are spread over FARGATE and FARGATE_SPOT: weight, and base (tasks always on that provider)."
  type = list(object({
    capacity_provider = string
    weight            = optional(number, 1)
    base              = optional(number, 0)
  }))
  default = [{ capacity_provider = "FARGATE" }]

  validation {
    condition     = length(var.capacity_provider_strategy) > 0 && alltrue([for s in var.capacity_provider_strategy : contains(["FARGATE", "FARGATE_SPOT"], s.capacity_provider)])
    error_message = "capacity_provider_strategy names FARGATE or FARGATE_SPOT."
  }
}

variable "statements" {
  description = "The application's own permissions, on its task role: what its code may do in AWS."
  type = list(object({
    effect    = optional(string, "Allow")
    actions   = list(string)
    resources = list(string)
  }))
  default = []

  validation {
    condition     = alltrue([for s in var.statements : !(contains(s.actions, "*") && contains(s.resources, "*")) && contains(["Allow", "Deny"], s.effect)])
    error_message = "No statement may allow every action on every resource; scope actions and resources (SKILLS.md)."
  }
}

variable "log_retention_days" {
  description = "How long the containers' logs are kept."
  type        = number
  default     = 365
}

variable "log_kms_key_arn" {
  description = "A key for the log group, whose policy lets CloudWatch Logs use it; null: CloudWatch's own encryption."
  type        = string
  default     = null
}
