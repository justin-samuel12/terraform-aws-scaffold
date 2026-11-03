locals {
  config_dir = coalesce(var.config_dir, path.root)
  has_file   = fileexists("${local.config_dir}/cluster.yml")
  cluster    = merge({}, try(yamldecode(file("${local.config_dir}/cluster.yml")), {}))
  apps       = { for name in fileset(local.config_dir, "*.yml") : trimsuffix(name, ".yml") => merge({}, try(yamldecode(file("${local.config_dir}/${name}")), {})) if name != "cluster.yml" }

  cluster_keys   = ["version", "admins", "viewers", "public_access_cidrs", "security_groups", "deletion_protection"]
  app_keys       = ["namespace", "service_account", "statement", "managed_policies"]
  statement_keys = ["effect", "actions", "resources", "condition"]

  network    = module.ip_plan.networks["${var.environment}/${var.region}"]
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  # A role's name means a role in this account; an ARN is used as written.
  people = { for k in ["admins", "viewers"] : k => [for e in try(tolist(local.cluster[k]), []) : tostring(e)] }
  role_arns = {
    for k, entries in local.people : k => [
      for e in entries : startswith(e, "arn:") ? e : "arn:${local.partition}:iam::${local.account_id}:role/${e}"
    ]
  }

  # One role per app, named <environment>-<app>-<region>: roles are global, and Vault's AWS auth knows an app by its role.
  identities = {
    for app, f in local.apps : "${var.environment}-${app}-${var.region}" => {
      app              = app
      namespace        = tostring(try(f.namespace, app))
      service_account  = tostring(try(f.service_account, app))
      managed_policies = [for p in try(tolist(f.managed_policies), []) : tostring(p)]
      statements = [for s in try(f.statement, []) : {
        effect    = try(tostring(s.effect), "Allow")
        actions   = [for a in try(tolist(s.actions), [s.actions], []) : tostring(a)]
        resources = [for r in try(tolist(s.resources), [s.resources], []) : tostring(r)]
        condition = [for c in try(s.condition, []) : { test = tostring(try(c.test, "?")), variable = tostring(try(c.variable, "?")), values = [for v in try(tolist(c.values), []) : tostring(v)] }]
      }]
    }
  }
  pairs = [for i in values(local.identities) : "${i.namespace}/${i.service_account}"]

  problems = concat(
    [for x in ["cluster.yml"] : "${join(", ", [for a in keys(local.apps) : "${a}.yml"])}: an app needs ${x} beside it, for the cluster it runs in" if !local.has_file && length(local.apps) > 0],
    [for x in ["cluster.yml"] : "${x}: keys are ${join(", ", local.cluster_keys)}" if local.has_file && !alltrue([for k in keys(local.cluster) : contains(local.cluster_keys, k)])],
    [for x in ["cluster.yml"] : "${x}: needs version, the Kubernetes version, such as 1.34; aws eks describe-cluster-versions lists the ones EKS offers" if local.has_file && !can(local.cluster.version)],
    [for x in ["cluster.yml"] : "${x}: version ${try(tostring(local.cluster.version), "?")} is written like 1.34, in quotes so YAML keeps it a string" if can(local.cluster.version) && !can(regex("^1\\.[0-9]{2}$", try(tostring(local.cluster.version), "")))],
    flatten([for k, entries in local.people : [for e in entries : "cluster.yml: ${e} in ${k} is neither an IAM role's name nor a role's ARN" if !can(regex("^(arn:aws[a-z-]*:iam::[0-9]{12}:role/.+|[A-Za-z0-9+=,.@_-]{1,64})$", e))]]),
    [for arn in setintersection(toset(local.role_arns.admins), toset(local.role_arns.viewers)) : "cluster.yml: ${arn} is in both admins and viewers"],
    [for c in try(tolist(local.cluster.public_access_cidrs), []) : "cluster.yml: public_access_cidrs ${c} is not a CIDR such as 203.0.113.10/32, or is the whole internet" if !can(cidrnetmask(c)) || tostring(c) == "0.0.0.0/0"],
    [for x in ["cluster.yml"] : "${x}: deletion_protection is true or false" if can(local.cluster.deletion_protection) && !can(tobool(local.cluster.deletion_protection))],
    [for x in ["cluster.yml"] : "${x}: ${var.environment}'s VPC in ${var.region} has no private tier for the cluster" if local.has_file && !contains(keys(local.network.subnets), "private")],
    [for app, f in local.apps : "${app}.yml: keys are ${join(", ", local.app_keys)}" if !alltrue([for k in keys(f) : contains(local.app_keys, k)])],
    [for app in keys(local.apps) : "${app}.yml: an app's name is lowercase letters, digits and hyphens, and ${var.environment}-${app}-${var.region} at most 64 characters" if !can(regex("^[a-z][a-z0-9-]*$", app)) || length("${var.environment}-${app}-${var.region}") > 64],
    [for name, i in local.identities : "${i.app}.yml: namespace and service_account are Kubernetes names: lowercase letters, digits and hyphens" if !can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", i.namespace)) || !can(regex("^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$", i.service_account))],
    [for p in distinct(local.pairs) : "${p}: more than one app runs as this namespace and service account; each app has its own" if length([for x in local.pairs : x if x == p]) > 1],
    [for app, f in local.apps : "${app}.yml: each statement takes ${join(", ", local.statement_keys)}, and needs actions and resources" if !alltrue([for s in try(f.statement, []) : can(s.actions) && can(s.resources) && alltrue([for k in try(keys(s), ["?"]) : contains(local.statement_keys, k)])])],
    [for app, f in local.apps : "${app}.yml: each condition takes test, variable and values, as in IAM" if !alltrue(flatten([for s in try(f.statement, []) : [for c in try(s.condition, []) : can(c.test) && can(c.variable) && can(tolist(c.values)) && length(keys(c)) == 3]]))],
    [for name, i in local.identities : "${i.app}.yml: no statement may allow every action on every resource" if anytrue([for s in i.statements : contains(s.actions, "*") && contains(s.resources, "*")])],
    [for name, i in local.identities : "${i.app}.yml: an app never takes AdministratorAccess, PowerUserAccess or IAMFullAccess" if length(setintersection(toset(i.managed_policies), toset(["AdministratorAccess", "PowerUserAccess", "IAMFullAccess"]))) > 0],
  )
  usable = length(local.problems) == 0
  build  = local.usable && local.has_file
}
