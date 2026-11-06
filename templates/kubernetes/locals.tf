locals {
  config_dir = coalesce(var.config_dir, "${path.root}/config")
  found = {
    for path in fileset(local.config_dir, "**/*.yml") : trimsuffix(basename(path), ".yml") => path...
  }
  files    = { for name, paths in local.found : name => yamldecode(file("${local.config_dir}/${sort(paths)[0]}")) }
  clusters = { for name, paths in local.found : name => local.files[name] if basename(dirname(sort(paths)[0])) == "cluster" }
  apps     = { for name, f in local.files : name => f if !contains(keys(local.clusters), name) }

  has_file = contains(keys(local.clusters), var.environment)
  cluster  = try(local.clusters[var.environment], {})

  cluster_keys     = ["version", "deletion_protection", "vpc_config", "access_entry"]
  vpc_keys         = ["subnet_ids", "security_group_ids", "endpoint_public_access", "public_access_cidrs"]
  entry_keys       = ["principal_arn", "access_policy_association"]
  association_keys = ["policy_arn", "access_scope"]
  scope_keys       = ["type", "namespaces"]
  app_keys         = ["namespace", "service_account", "statement", "managed_policy_arns"]
  statement_keys   = ["effect", "actions", "resources", "condition"]
  refused_policies = ["AdministratorAccess", "PowerUserAccess", "IAMFullAccess"]

  network      = module.ip_plan.networks["${var.environment}/${var.region}"]
  subnet_names = flatten([for tier in keys(local.network.subnets) : [for zone in local.network.zones : "${tier}-${split("-", zone)[1]}"]])
  account_id   = data.aws_caller_identity.current.account_id
  partition    = data.aws_partition.current.partition

  vpc_config      = try(local.cluster.vpc_config, {})
  subnets         = [for s in try(tolist(local.vpc_config.subnet_ids), []) : tostring(s)]
  security_groups = [for g in try(tolist(local.vpc_config.security_group_ids), []) : tostring(g)]
  public          = try(tobool(local.vpc_config.endpoint_public_access), false)
  public_cidrs    = [for c in try(tolist(local.vpc_config.public_access_cidrs), []) : tostring(c)]

  raw_entries = try([for e in local.cluster.access_entry : e if !can(keys(local.cluster.access_entry))], [])
  entries = [
    for e in local.raw_entries : {
      principal = try(tostring(e.principal_arn), "")
      associations = [
        for a in try([for a in e.access_policy_association : a if !can(keys(e.access_policy_association))], []) : {
          policy_arn = try(tostring(a.policy_arn), "")
          access_scope = {
            type       = try(tostring(a.access_scope.type), "")
            namespaces = [for n in try(tolist(a.access_scope.namespaces), []) : tostring(n)]
          }
        }
      ]
    }
  ]
  access_entries = [
    for e in local.entries : {
      principal_arn              = startswith(e.principal, "arn:") ? e.principal : "arn:${local.partition}:iam::${local.account_id}:role/${e.principal}"
      access_policy_associations = e.associations
    }
  ]
  principals = [for e in local.access_entries : e.principal_arn]

  identities = {
    for app, f in local.apps : "${var.environment}-${app}-${var.region}" => {
      app             = app
      namespace       = try(tostring(f.namespace), "")
      service_account = try(tostring(f.service_account), "")
      policy_arns     = [for p in try(tolist(f.managed_policy_arns), []) : tostring(p)]
      statements = [for s in try(f.statement, []) : {
        effect    = try(tostring(s.effect), "Allow")
        actions   = [for a in try(tolist(s.actions), [s.actions], []) : tostring(a)]
        resources = [for r in try(tolist(s.resources), [s.resources], []) : tostring(r)]
        condition = [for c in try(s.condition, []) : { test = tostring(try(c.test, "?")), variable = tostring(try(c.variable, "?")), values = [for v in try(tolist(c.values), []) : tostring(v)] }]
      }]
    }
  }
  pairs = [for i in values(local.identities) : "${i.namespace}/${i.service_account}"]

  file = "cluster/${var.environment}.yml"
  problems = concat(
    [for name, paths in local.found : "${name}.yml is in more than one folder (${join(", ", sort(paths))}); a file's name is what it builds, so it must be unique" if length(paths) > 1],
    [for name in keys(local.clusters) : "cluster/${name}.yml: the cluster is named for its environment, so its file is ${local.file}" if name != var.environment],
    [for x in [local.file] : "${join(", ", [for a in keys(local.apps) : "${a}.yml"])}: an app needs its cluster, ${x}" if !local.has_file && length(local.apps) > 0],
    [for x in [local.file] : "${x}: keys are ${join(", ", local.cluster_keys)}: aws_eks_cluster's, and access_entry for aws_eks_access_entry" if local.has_file && !alltrue([for k in try(keys(local.cluster), ["?"]) : contains(local.cluster_keys, k)])],
    [for x in [local.file] : "${x}: needs version, the Kubernetes version, such as 1.34; aws eks describe-cluster-versions lists the ones EKS offers" if local.has_file && !can(local.cluster.version)],
    [for x in [local.file] : "${x}: version ${try(tostring(local.cluster.version), "?")} is written like 1.34, in quotes so YAML keeps it a string" if can(local.cluster.version) && !can(regex("^1\\.[0-9]{2}$", try(tostring(local.cluster.version), "")))],
    [for x in [local.file] : "${x}: needs deletion_protection, true or false" if local.has_file && !can(tobool(local.cluster.deletion_protection))],
    [for x in [local.file] : "${x}: vpc_config takes ${join(", ", local.vpc_keys)}, and needs subnet_ids and endpoint_public_access" if local.has_file && (!alltrue([for k in try(keys(local.cluster.vpc_config), ["?"]) : contains(local.vpc_keys, k)]) || !can(tolist(local.cluster.vpc_config.subnet_ids)) || !can(tobool(local.cluster.vpc_config.endpoint_public_access)))],
    [for x in [local.file] : "${x}: vpc_config.subnet_ids names subnets in at least two zones" if local.has_file && can(tolist(local.cluster.vpc_config.subnet_ids)) && length(local.subnets) < 2],
    [for s in local.subnets : "${local.file}: vpc_config.subnet_ids ${s} is not a subnet of ${var.environment}'s VPC in ${var.region}: ${join(", ", local.subnet_names)}" if !startswith(s, "subnet-") && !contains(local.subnet_names, s)],
    [for x in [local.file] : "${x}: vpc_config.public_access_cidrs is set only with endpoint_public_access: true" if !local.public && length(local.public_cidrs) > 0],
    [for x in [local.file] : "${x}: vpc_config.endpoint_public_access: true needs public_access_cidrs, the addresses that may reach the API" if local.public && length(local.public_cidrs) == 0],
    [for c in local.public_cidrs : "${local.file}: public_access_cidrs ${c} is not a CIDR such as 203.0.113.10/32, or is the whole internet" if !can(cidrnetmask(c)) || c == "0.0.0.0/0"],
    [for x in [local.file] : "${x}: access_entry is a list of entries" if try(local.cluster.access_entry, null) != null && (can(keys(local.cluster.access_entry)) || !can([for e in local.cluster.access_entry : e]))],
    [for e in local.raw_entries : "${local.file}: each access_entry takes ${join(", ", local.entry_keys)}, and needs both" if !alltrue([for k in try(keys(e), ["?"]) : contains(local.entry_keys, k)]) || !can(e.principal_arn) || can(keys(e.access_policy_association)) || !can([for a in e.access_policy_association : a])],
    [for e in local.entries : "${local.file}: principal_arn ${e.principal} is neither an IAM role's name nor a role's ARN" if !can(regex("^(arn:aws[a-z-]*:iam::[0-9]{12}:role/.+|[A-Za-z0-9+=,.@_-]{1,64})$", e.principal))],
    [for p in distinct(local.principals) : "${local.file}: ${p} has more than one access_entry; give it one, with each policy under access_policy_association" if length([for x in local.principals : x if x == p]) > 1],
    flatten([for e in local.raw_entries : [for a in try([for a in e.access_policy_association : a if !can(keys(e.access_policy_association))], []) : "${local.file}: each access_policy_association takes ${join(", ", local.association_keys)}, and access_scope takes ${join(", ", local.scope_keys)}" if !alltrue([for k in try(keys(a), ["?"]) : contains(local.association_keys, k)]) || !alltrue([for k in try(keys(a.access_scope), ["?"]) : contains(local.scope_keys, k)])]]),
    flatten([for e in local.entries : [for a in e.associations : "${local.file}: policy_arn ${a.policy_arn} for ${e.principal} is an EKS access policy's ARN, such as arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy" if !can(regex("^arn:aws[a-z-]*:eks::aws:cluster-access-policy/[A-Za-z]+$", a.policy_arn))]]),
    flatten([for e in local.entries : [for a in e.associations : "${local.file}: access_scope for ${e.principal} is type cluster, or type namespace with namespaces" if !(a.access_scope.type == "cluster" && length(a.access_scope.namespaces) == 0) && !(a.access_scope.type == "namespace" && length(a.access_scope.namespaces) > 0)]]),
    [for x in [local.file] : "${x}: ${var.environment}'s VPC in ${var.region} has no private tier for the cluster" if local.has_file && !contains(keys(local.network.subnets), "private")],
    [for app, f in local.apps : "${app}.yml: keys are ${join(", ", local.app_keys)}: namespace and service_account as aws_eks_pod_identity_association takes them, statement and managed_policy_arns for its role" if !alltrue([for k in try(keys(f), ["?"]) : contains(local.app_keys, k)])],
    [for app in keys(local.apps) : "${app}.yml: an app's name is lowercase letters, digits and hyphens, and ${var.environment}-${app}-${var.region} at most 64 characters" if !can(regex("^[a-z][a-z0-9-]*$", app)) || length("${var.environment}-${app}-${var.region}") > 64],
    [for name, i in local.identities : "${i.app}.yml: needs namespace and service_account, Kubernetes names: lowercase letters, digits and hyphens" if !can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", i.namespace)) || !can(regex("^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$", i.service_account))],
    [for p in distinct(local.pairs) : "${p}: more than one app runs as this namespace and service account; each app has its own" if length([for x in local.pairs : x if x == p]) > 1],
    [for app, f in local.apps : "${app}.yml: each statement takes ${join(", ", local.statement_keys)}, and needs actions and resources" if !alltrue([for s in try(f.statement, []) : can(s.actions) && can(s.resources) && alltrue([for k in try(keys(s), ["?"]) : contains(local.statement_keys, k)])])],
    [for app, f in local.apps : "${app}.yml: each condition takes test, variable and values, as in IAM" if !alltrue(flatten([for s in try(f.statement, []) : [for c in try(s.condition, []) : can(c.test) && can(c.variable) && can(tolist(c.values)) && length(keys(c)) == 3]]))],
    [for name, i in local.identities : "${i.app}.yml: no statement may allow every action on every resource" if anytrue([for s in i.statements : contains(s.actions, "*") && contains(s.resources, "*")])],
    flatten([for name, i in local.identities : [for p in i.policy_arns : "${i.app}.yml: managed_policy_arns ${p} is a policy's ARN, such as arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess" if !can(regex("^arn:aws[a-z-]*:iam::(aws|[0-9]{12}):policy/.+$", p))]]),
    [for name, i in local.identities : "${i.app}.yml: an app never takes ${join(", ", local.refused_policies)}" if anytrue([for p in i.policy_arns : contains([for r in local.refused_policies : "policy/${r}"], try(regex("policy/.+$", p), ""))])],
  )
  usable = length(local.problems) == 0
  build  = local.usable && local.has_file
}
