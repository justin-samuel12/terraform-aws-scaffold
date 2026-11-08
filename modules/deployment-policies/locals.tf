locals {
  arn          = "arn:${var.partition}"
  iam          = "${local.arn}:iam::${var.account_id}"
  hub_iam      = "${local.arn}:iam::${var.hub_account_id}"
  bucket       = "${local.arn}:s3:::${var.state_bucket}"
  shared       = var.environment == "shared"
  role_path    = "/deployed/"
  boundary_arn = { for name in keys(var.duties) : name => "${local.iam}:policy/terraform-boundary-${var.environment}-${name}" }
  network_role = "${local.hub_iam}:role/terraform-network-${var.environment}"
  dns_role     = "${local.hub_iam}:role/deployed/dns-${var.environment}"
  dns_read     = "${local.hub_iam}:role/terraform-dns-read-${var.environment}"
  oidc_arn     = "${local.iam}:oidc-provider/${var.github_oidc_host}"

  components = sort(flatten([for d in values(var.duties) : d.components]))

  key_dir = {
    for c in concat(local.components, ["*"]) : c => replace(replace(replace(replace(var.state_key_format,
    "{region}", "*"), "{environment}", var.environment), "{component}", c), "{account_id}", var.account_id)
  }
  state_objects       = { for c, dir in local.key_dir : c => "${local.bucket}/${dir}/terraform.tfstate*" }
  environment_objects = [local.state_objects["*"]]
  environment_prefixes = [
    local.key_dir["*"],
    "${local.key_dir["*"]}/*",
    "env:/*",
  ]
  environment_plans = "${local.bucket}/plans/*/${var.environment}/*"

  duty_objects  = { for name, d in var.duties : name => [for c in d.components : local.state_objects[c]] }
  duty_prefixes = { for name, d in var.duties : name => concat(flatten([for c in d.components : [local.key_dir[c], "${local.key_dir[c]}/*"]]), ["env:/*"]) }
  duty_plans    = { for name, d in var.duties : name => [for c in d.components : "${local.bucket}/plans/*/${var.environment}/${c}/*"] }

  no_reads = ["backup-storage", "sts"]
  services = sort(distinct(concat(
    flatten([for d in values(var.duties) : [for a in d.actions : split(":", a)[0]]]),
    ["acm", "cloudwatch", "ec2", "elasticloadbalancing", "iam", "kms", "logs", "ram", "route53", "route53resolver", "ssm", "tag"],
  )))
  read_services = [for s in local.services : s if !contains(concat(local.no_reads, ["s3"]), s)]
  no_such_reads = [
    "access-analyzer:Describe*", "application-autoscaling:Get*", "autoscaling:List*", "codedeploy:Describe*", "eks:Get*",
    "elasticfilesystem:Get*", "elasticloadbalancing:List*", "events:Get*", "iam:Describe*", "lambda:Describe*", "ram:Describe*",
    "rds:Get*", "route53:Describe*", "route53resolver:Describe*", "sns:Describe*", "sqs:Describe*", "tag:List*",
  ]
  reads = concat(
    [for a in flatten([for s in local.read_services : ["${s}:Describe*", "${s}:Get*", "${s}:List*"]]) : a if !contains(local.no_such_reads, a)],
    contains(local.services, "codedeploy") ? ["codedeploy:BatchGet*"] : [],
    local.s3_reads,
  )
  s3_reads = [
    "s3:GetBucket*", "s3:GetLifecycleConfiguration", "s3:GetEncryptionConfiguration", "s3:GetReplicationConfiguration",
    "s3:GetAccelerateConfiguration", "s3:GetIntelligentTieringConfiguration", "s3:GetInventoryConfiguration",
    "s3:GetMetricsConfiguration", "s3:GetAnalyticsConfiguration",
    "s3:GetAccountPublicAccessBlock", "s3:ListAllMyBuckets", "s3:ListBucket",
  ]
  describe_and_list = [for a in local.reads : a if !strcontains(a, ":Get") && !strcontains(a, ":BatchGet")]
  uses              = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey*", "kms:ReEncrypt*", "kms:CreateGrant", "iam:PassRole", "ecr:BatchGetImage", "ecr:BatchCheckLayerAvailability"]

  data_reads = [
    "secretsmanager:BatchGetSecretValue",
    "ssm:GetParameter*",
    "logs:GetLogEvents",
    "logs:GetLogRecord",
    "logs:FilterLogEvents",
    "logs:StartQuery",
    "logs:GetQueryResults",
    "ec2:GetPasswordData",
    "ec2:GetConsoleOutput",
    "ec2:GetConsoleScreenshot",
    "rds:DownloadDBLogFilePortion",
    "rds:DownloadCompleteDBLogFile",
    "sqs:ReceiveMessage",
    "ecr:GetAuthorizationToken",
    "ecr:GetDownloadUrlForLayer",
    "ecr:BatchGetImage",
  ]

  iam_writes = [
    "iam:Add*", "iam:Attach*", "iam:Create*", "iam:Delete*", "iam:Detach*", "iam:Pass*", "iam:Put*",
    "iam:Remove*", "iam:Set*", "iam:Tag*", "iam:Untag*", "iam:Update*", "iam:Upload*",
  ]
  pipeline_identity = [
    "${local.arn}:iam::*:role/terraform-*",
    "${local.arn}:iam::*:policy/terraform-*",
    "${local.arn}:iam::*:instance-profile/terraform-*",
    "${local.arn}:iam::*:oidc-provider/${var.github_oidc_host}",
  ]

  central_network = [
    "ec2:CreateTransitGateway",
    "ec2:DeleteTransitGateway",
    "ec2:ModifyTransitGateway",
    "ec2:CreateTransitGatewayRoute*",
    "ec2:DeleteTransitGatewayRoute*",
    "ec2:ReplaceTransitGatewayRoute",
    "ec2:AssociateTransitGatewayRouteTable",
    "ec2:DisassociateTransitGatewayRouteTable",
    "ec2:EnableTransitGatewayRouteTablePropagation",
    "ec2:DisableTransitGatewayRouteTablePropagation",
    "ec2:AcceptTransitGateway*",
    "ec2:RejectTransitGateway*",
    "ec2:CreateTransitGatewayPeering*",
    "ec2:DeleteTransitGatewayPeering*",
    "ec2:CreateTransitGatewayConnect*",
    "ec2:CreateTransitGatewayPolicyTable",
    "ec2:CreateTransitGatewayPrefixListReference",
    "ec2:ModifyTransitGatewayPrefixListReference",
    "ec2:CreateTransitGatewayMulticastDomain",
    "ec2:CreateVpn*",
    "ec2:DeleteVpn*",
    "ec2:ModifyVpn*",
    "ec2:AttachVpnGateway",
    "ec2:DetachVpnGateway",
    "ec2:CreateCustomerGateway",
    "ec2:DeleteCustomerGateway",
    "ec2:EnableVgwRoutePropagation",
    "ec2:DisableVgwRoutePropagation",
  ]

  spoke_network = [
    "ec2:CreateVpc*",
    "ec2:DeleteVpc*",
    "ec2:ModifyVpc*",
    "ec2:AssociateVpc*",
    "ec2:DisassociateVpc*",
    "ec2:AcceptVpcPeeringConnection",
    "ec2:RejectVpcPeeringConnection",
    "ec2:CreateSubnet*",
    "ec2:DeleteSubnet*",
    "ec2:ModifySubnet*",
    "ec2:AssociateSubnet*",
    "ec2:DisassociateSubnet*",
    "ec2:CreateRoute*",
    "ec2:DeleteRoute*",
    "ec2:ReplaceRoute*",
    "ec2:AssociateRouteTable",
    "ec2:DisassociateRouteTable",
    "ec2:CreateNetworkAcl*",
    "ec2:DeleteNetworkAcl*",
    "ec2:ReplaceNetworkAcl*",
    "ec2:*InternetGateway",
    "ec2:*NatGateway",
    "ec2:CreateFlowLogs",
    "ec2:DeleteFlowLogs",
    "ec2:CreateDhcpOptions",
    "ec2:DeleteDhcpOptions",
    "ec2:AssociateDhcpOptions",
    "ec2:CreateTransitGatewayVpcAttachment",
    "ec2:DeleteTransitGatewayVpcAttachment",
    "ec2:ModifyTransitGatewayVpcAttachment",
  ]

  protect = { for name in keys(var.duties) : name => [
    {
      Sid      = "ProtectThePipelinesIdentity"
      Effect   = "Deny"
      Action   = local.iam_writes
      Resource = local.pipeline_identity
    },
    {
      Sid      = "NoLongLivedCredentials"
      Effect   = "Deny"
      Action   = ["iam:CreateUser", "iam:CreateAccessKey", "iam:CreateLoginProfile", "iam:UpdateLoginProfile", "iam:CreateServiceSpecificCredential", "iam:UploadSSHPublicKey"]
      Resource = "*"
    },
    {
      Sid      = "NoOrganizationOrAccountChanges"
      Effect   = "Deny"
      Action   = ["organizations:*", "account:*"]
      Resource = "*"
    },
    {
      Sid      = "ProtectTheAuditTrail"
      Effect   = "Deny"
      Action   = ["cloudtrail:StopLogging", "cloudtrail:DeleteTrail", "cloudtrail:UpdateTrail", "cloudtrail:PutEventSelectors"]
      Resource = "*"
    },
    {
      Sid       = "RolesCarryTheBoundary"
      Effect    = "Deny"
      Action    = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"]
      Resource  = "*"
      Condition = { StringNotEquals = { "iam:PermissionsBoundary" = local.boundary_arn[name] } }
    },
    {
      Sid      = "BoundariesStay"
      Effect   = "Deny"
      Action   = ["iam:DeleteRolePermissionsBoundary", "iam:DeleteUserPermissionsBoundary", "iam:PutUserPermissionsBoundary"]
      Resource = "*"
    },
  ] }

  no_admin_policies = {
    Sid       = "NoAdministratorPoliciesAndNoBoundaryAsAPermission"
    Effect    = "Deny"
    Action    = ["iam:AttachRolePolicy"]
    Resource  = "*"
    Condition = { ArnLike = { "iam:PolicyARN" = ["${local.arn}:iam::aws:policy/AdministratorAccess", "${local.arn}:iam::aws:policy/IAMFullAccess", "${local.arn}:iam::aws:policy/PowerUserAccess", "${local.arn}:iam::*:policy/terraform-*"] } }
  }

  protect_state = {
    Sid    = "ProtectTheStateBucket"
    Effect = "Deny"
    Action = [
      "s3:DeleteBucket*", "s3:PutBucket*", "s3:PutLifecycleConfiguration", "s3:PutEncryptionConfiguration",
      "s3:PutReplicationConfiguration", "s3:PutAccelerateConfiguration", "s3:PutObjectRetention",
      "s3:PutObjectLegalHold", "s3:BypassGovernanceRetention", "s3:DeleteObjectVersion",
    ]
    Resource = [local.bucket, "${local.bucket}/*"]
  }

  peering_connections = ["${local.arn}:ec2:*:*:vpc-peering-connection/*"]
  other_environments = {
    for name, d in var.duties : name => [for s in [
      {
        Sid         = "OnlyReadOtherEnvironments"
        Effect      = "Deny"
        NotAction   = concat(local.describe_and_list, d.across)
        NotResource = local.peering_connections
        Condition = {
          Null            = { "aws:ResourceTag/Environment" = "false" }
          StringNotEquals = { "aws:ResourceTag/Environment" = [var.environment, "shared"] }
        }
      },
    ] : s if !local.shared]
  }

  peering_of_others = {
    Sid      = "PeeringOfOtherEnvironmentsIsOnlyAccepted"
    Effect   = "Deny"
    Action   = ["ec2:DeleteVpcPeeringConnection", "ec2:RejectVpcPeeringConnection", "ec2:ModifyVpcPeeringConnectionOptions", "ec2:DeleteTags", "ec2:CreateTags"]
    Resource = local.peering_connections
    Condition = {
      Null            = { "aws:ResourceTag/Environment" = "false" }
      StringNotEquals = { "aws:ResourceTag/Environment" = var.environment }
    }
  }

  secrets_of_others = {
    Sid      = "NoSecretOfAnotherEnvironmentOrUntagged"
    Effect   = "Deny"
    Action   = "secretsmanager:GetSecretValue"
    Resource = "*"
    Condition = {
      StringNotEqualsIfExists = { "aws:ResourceTag/Environment" = [var.environment] }
    }
  }

  runtime_data = ["secretsmanager:GetSecretValue", "ssm:GetParameter*", "lambda:GetFunction", "logs:GetLogEvents", "logs:FilterLogEvents", "sqs:ReceiveMessage", "sqs:SendMessage", "sns:Publish"]

  ownership_keys = ["Environment", "Component"]
  untag_actions = [
    "acm:RemoveTagsFromCertificate", "application-autoscaling:UntagResource", "autoscaling:DeleteTags", "backup:UntagResource",
    "cloudfront:UntagResource", "cloudwatch:UntagResource", "codedeploy:UntagResource", "ds:RemoveTagsFromResource", "ec2:DeleteTags",
    "ecr:UntagResource", "ecs:UntagResource", "eks:UntagResource", "elasticfilesystem:UntagResource", "elasticloadbalancing:RemoveTags",
    "events:UntagResource", "iam:UntagRole", "iam:UntagPolicy", "iam:UntagInstanceProfile", "kms:UntagResource", "lambda:UntagResource",
    "logs:UntagResource", "ram:UntagResource", "rds:RemoveTagsFromResource", "route53resolver:UntagResource", "secretsmanager:UntagResource",
    "sns:UntagResource", "sqs:UntagQueue", "ssm:RemoveTagsFromResource", "wafv2:UntagResource",
  ]
  must_be_tagged = [
    "ec2:TerminateInstances", "ec2:StopInstances", "ec2:ModifyInstanceAttribute", "ec2:DeleteVolume", "rds:DeleteDBInstance", "rds:ModifyDBInstance",
    "rds:DeleteDBCluster", "rds:ModifyDBCluster", "kms:ScheduleKeyDeletion", "kms:DisableKey", "kms:PutKeyPolicy", "secretsmanager:DeleteSecret",
    "secretsmanager:PutSecretValue", "elasticfilesystem:DeleteFileSystem", "eks:DeleteCluster", "lambda:DeleteFunction", "lambda:UpdateFunctionCode",
    "sqs:DeleteQueue", "elasticloadbalancing:DeleteLoadBalancer", "ecs:DeleteCluster",
  ]
  created_tagged = [
    "kms:CreateKey", "secretsmanager:CreateSecret", "rds:CreateDBInstance", "rds:CreateDBCluster", "sqs:CreateQueue", "sns:CreateTopic",
    "lambda:CreateFunction", "eks:CreateCluster", "elasticloadbalancing:CreateLoadBalancer", "elasticfilesystem:CreateFileSystem",
    "logs:CreateLogGroup", "ecr:CreateRepository", "iam:CreateRole",
  ]
  created_tagged_ec2 = {
    "ec2:CreateVolume"        = "volume"
    "ec2:CreateVpc"           = "vpc"
    "ec2:CreateSubnet"        = "subnet"
    "ec2:CreateSecurityGroup" = "security-group"
  }
  tag_ownership = [
    {
      Sid       = "OwnershipTagsAreNeverRemoved"
      Effect    = "Deny"
      Action    = local.untag_actions
      Resource  = "*"
      Condition = { "ForAnyValue:StringEquals" = { "aws:TagKeys" = local.ownership_keys } }
    },
    {
      Sid       = "AllTagsAreNeverRemovedAtOnce"
      Effect    = "Deny"
      Action    = "ec2:DeleteTags"
      Resource  = "*"
      Condition = { Null = { "aws:TagKeys" = "true" } }
    },
    {
      Sid       = "AServerIsOnlyTaggedAsItIsCreated"
      Effect    = "Deny"
      Action    = "ec2:CreateTags"
      Resource  = "${local.arn}:ec2:*:*:instance/*"
      Condition = { Null = { "ec2:CreateAction" = "true" }, "ForAnyValue:StringEquals" = { "aws:TagKeys" = local.ownership_keys } }
    },
    {
      Sid       = "AnUntaggedResourceIsNotOurs"
      Effect    = "Deny"
      Action    = local.must_be_tagged
      Resource  = "*"
      Condition = { Null = { "aws:ResourceTag/Environment" = "true" } }
    },
    {
      Sid       = "CreatedWithItsEnvironment"
      Effect    = "Deny"
      Action    = local.created_tagged
      Resource  = "*"
      Condition = { Null = { "aws:RequestTag/Environment" = "true" } }
    },
    {
      Sid       = "CreatedWithItsEnvironmentInEc2"
      Effect    = "Deny"
      Action    = keys(local.created_tagged_ec2)
      Resource  = [for t in values(local.created_tagged_ec2) : "${local.arn}:ec2:*:*:${t}/*"]
      Condition = { Null = { "aws:RequestTag/Environment" = "true" } }
    },
  ]

  create_here = {
    Sid       = "CreateOnlyInThisEnvironment"
    Effect    = "Deny"
    Action    = "*"
    Resource  = "*"
    Condition = { Null = { "aws:RequestTag/Environment" = "false" }, StringNotEquals = { "aws:RequestTag/Environment" = var.environment } }
  }

  duty = {
    for name, d in var.duties : name => {
      all_ec2      = contains(d.actions, "ec2:*")
      s3           = [for a in d.actions : a if a == "s3:*"]
      others       = [for a in d.actions : a if a != "s3:*"]
      central      = name != "hub" && anytrue([for a in d.actions : startswith(a, "ec2:")])
      spoke        = contains(d.actions, "ec2:*") && !contains(["hub", "network"], name)
      assumes      = name == "network" ? [local.network_role, local.dns_role] : name == "workload" ? [local.dns_role] : []
      creates_role = name != "pipeline"
      uses         = distinct(concat(local.reads, local.uses, d.uses, d.across))
    }
  }

  apply_allow = {
    for name, d in var.duties : name => concat(
      [for s in [{
        Sid      = "Deploy"
        Effect   = "Allow"
        Action   = local.duty[name].others
        Resource = "*"
      }] : s if !(length(local.duty[name].others) == 0)],
      [for s in [{
        Sid      = "DeployThisEnvironmentsBuckets"
        Effect   = "Allow"
        Action   = local.duty[name].s3
        Resource = "${local.arn}:s3:::${var.environment}-*"
      }] : s if !(length(local.duty[name].s3) == 0)],
      [for s in [
        {
          Sid       = "RolesWithTheBoundary"
          Effect    = "Allow"
          Action    = ["iam:CreateRole", "iam:PutRolePermissionsBoundary", "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:DeleteRole", "iam:UpdateRole", "iam:UpdateRoleDescription", "iam:UpdateAssumeRolePolicy"]
          Resource  = concat(["${local.iam}:role${local.role_path}*"], [for r in d.roles : "${local.iam}:role/${r}"])
          Condition = { StringEquals = { "iam:PermissionsBoundary" = local.boundary_arn[name] } }
        },
        {
          Sid    = "DeployedRolesProfilesAndPolicies"
          Effect = "Allow"
          Action = [
            "iam:TagRole", "iam:UntagRole", "iam:PassRole",
            "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile", "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile", "iam:TagInstanceProfile", "iam:UntagInstanceProfile",
            "iam:CreatePolicy", "iam:CreatePolicyVersion", "iam:DeletePolicy", "iam:DeletePolicyVersion", "iam:SetDefaultPolicyVersion", "iam:TagPolicy", "iam:UntagPolicy",
          ]
          Resource = concat(["${local.iam}:role${local.role_path}*", "${local.iam}:instance-profile${local.role_path}*", "${local.iam}:policy${local.role_path}*"], [for r in d.roles : "${local.iam}:role/${r}"])
        },
        {
          Sid      = "ServiceLinkedRoles"
          Effect   = "Allow"
          Action   = "iam:CreateServiceLinkedRole"
          Resource = "${local.iam}:role/aws-service-role/*"
        },
      ] : s if local.duty[name].creates_role],
      [for s in [{
        Sid      = "AssumeTheNarrowCrossAccountRoles"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = local.duty[name].assumes
      }] : s if !(length(local.duty[name].assumes) == 0)],
    )
  }

  apply_state = {
    for name, d in var.duties : name => concat(
      [
        {
          Sid      = "OwnState"
          Effect   = "Allow"
          Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
          Resource = local.duty_objects[name]
        },
        {
          Sid       = "ListOwnState"
          Effect    = "Allow"
          Action    = "s3:ListBucket"
          Resource  = local.bucket
          Condition = { StringLike = { "s3:prefix" = local.duty_prefixes[name] } }
        },
        {
          Sid       = "ClaimAPlanOnce"
          Effect    = "Allow"
          Action    = "s3:PutObject"
          Resource  = [for c in d.components : "${local.bucket}/applied/*/${var.environment}/${c}/*"]
          Condition = { StringEquals = { "s3:if-none-match" = "*" } }
        },
        {
          Sid      = "TakeApprovedPlans"
          Effect   = "Allow"
          Action   = ["s3:GetObject", "s3:DeleteObject"]
          Resource = local.duty_plans[name]
        },
      ],
    )
  }

  apply_limits = {
    for name, d in var.duties : name => concat(
      local.protect[name],
      [local.protect_state, local.no_admin_policies],
      [for s in [{
        Sid      = "NoCentralNetworkChanges"
        Effect   = "Deny"
        Action   = local.central_network
        Resource = "*"
      }] : s if local.duty[name].central],
      [for s in [{
        Sid      = "NoChangesToTheEnvironmentsNetwork"
        Effect   = "Deny"
        Action   = local.spoke_network
        Resource = "*"
      }] : s if local.duty[name].spoke],
      [for s in [{
        Sid      = "AssumeNoOtherRole"
        Effect   = "Deny"
        Action   = ["sts:AssumeRole", "sts:AssumeRoleWithWebIdentity", "sts:AssumeRoleWithSAML"]
        Resource = "*"
      }] : s if length(local.duty[name].assumes) == 0],
      [for s in [{
        Sid         = "AssumeNoOtherRole"
        Effect      = "Deny"
        Action      = ["sts:AssumeRole", "sts:AssumeRoleWithWebIdentity", "sts:AssumeRoleWithSAML"]
        NotResource = local.duty[name].assumes
      }] : s if length(local.duty[name].assumes) > 0],
    )
  }

  apply_environment = {
    for name, d in var.duties : name => concat(
      local.other_environments[name],
      [for s in [local.peering_of_others] : s if !local.shared],
      [
        {
          Sid         = "ChangeOnlyThisEnvironment"
          Effect      = "Deny"
          NotAction   = local.duty[name].uses
          NotResource = local.peering_connections
          Condition = {
            Null            = { "aws:ResourceTag/Environment" = "false" }
            StringNotEquals = { "aws:ResourceTag/Environment" = var.environment }
          }
        },
        local.create_here,
      ],
    )
  }

  apply_ownership = {
    for name, d in var.duties : name => concat(local.tag_ownership, [
      {
        Sid       = "PassOnlyThisDutysRolesAndTheIamStacks"
        Effect    = "Deny"
        Action    = "iam:PassRole"
        Resource  = "*"
        Condition = { Null = { "aws:ResourceTag/Component" = "false" }, StringNotEquals = { "aws:ResourceTag/Component" = concat(d.components, ["iam"]) } }
      },
      {
        Sid       = "ChangeOnlyThisDutysComponents"
        Effect    = "Deny"
        NotAction = local.duty[name].uses
        Resource  = "*"
        Condition = {
          Null            = { "aws:ResourceTag/Component" = "false" }
          StringNotEquals = { "aws:ResourceTag/Component" = d.components }
        }
      },
      {
        Sid       = "CreateOnlyForThisDutysComponents"
        Effect    = "Deny"
        Action    = "*"
        Resource  = "*"
        Condition = { Null = { "aws:RequestTag/Component" = "false" }, StringNotEquals = { "aws:RequestTag/Component" = d.components } }
      },
    ])
  }

  read = [
    {
      Sid      = "Read"
      Effect   = "Allow"
      Action   = [for a in local.reads : a if !startswith(a, "s3:")]
      Resource = "*"
    },
    {
      Sid         = "ReadBucketsButNotTheStateBucket"
      Effect      = "Allow"
      Action      = local.s3_reads
      NotResource = [local.bucket, "${local.bucket}/*"]
    },
  ]

  environment_state = [
    {
      Sid       = "DecryptThisEnvironmentsSecretsThroughSecretsManager"
      Effect    = "Allow"
      Action    = "kms:Decrypt"
      Resource  = "${local.arn}:kms:*:${var.account_id}:key/*"
      Condition = { StringEquals = { "aws:ResourceTag/Environment" = var.environment }, StringLike = { "kms:ViaService" = "secretsmanager.*.amazonaws.com" } }
    },
    {
      Sid      = "ReadThisEnvironmentsState"
      Effect   = "Allow"
      Action   = "s3:GetObject"
      Resource = local.environment_objects
    },
    {
      Sid       = "ListThisEnvironmentsState"
      Effect    = "Allow"
      Action    = "s3:ListBucket"
      Resource  = local.bucket
      Condition = { StringLike = { "s3:prefix" = local.environment_prefixes } }
    },
  ]

  applied = "${local.bucket}/applied/*/${var.environment}/*"
  only_new_objects = {
    Sid       = "NeverOverwriteARecord"
    Effect    = "Deny"
    Action    = "s3:PutObject"
    Resource  = [local.environment_plans, local.applied]
    Condition = { Null = { "s3:if-none-match" = "true" } }
  }

  plan = concat(local.environment_state, [
    local.secrets_of_others,
    {
      Sid      = "NeverTouchStoredPlans"
      Effect   = "Deny"
      Action   = "s3:*"
      Resource = ["${local.bucket}/plans/*", "${local.bucket}/applied/*"]
    },
    {
      Sid         = "ReadNoObjectButThisEnvironmentsState"
      Effect      = "Deny"
      Action      = "s3:GetObject*"
      NotResource = local.environment_objects
    },
    {
      Sid      = "ReadNoSecretsOrData"
      Effect   = "Deny"
      Action   = local.data_reads
      Resource = "*"
    },
    {
      Sid      = "ReadTheHubsZonesThroughItsReadRole"
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = local.dns_read
    },
    {
      Sid         = "AssumeNoOtherRole"
      Effect      = "Deny"
      Action      = ["sts:AssumeRole", "sts:AssumeRoleWithWebIdentity", "sts:AssumeRoleWithSAML"]
      NotResource = local.dns_read
    },
  ])

  propose = concat(local.environment_state, [
    local.secrets_of_others,
    local.only_new_objects,
    {
      Sid      = "TakeTheStateLock"
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:DeleteObject"]
      Resource = "${local.bucket}/${local.key_dir["*"]}/terraform.tfstate.tflock"
    },
    {
      Sid      = "StorePlansForReview"
      Effect   = "Allow"
      Action   = "s3:PutObject"
      Resource = local.environment_plans
    },
    {
      Sid      = "ReadTheHubsZonesThroughItsReadRole"
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = local.dns_read
    },
    {
      Sid         = "AssumeNoOtherRole"
      Effect      = "Deny"
      Action      = ["sts:AssumeRole", "sts:AssumeRoleWithWebIdentity", "sts:AssumeRoleWithSAML"]
      NotResource = local.dns_read
    },
  ])

  boundary_statements = {
    for name, d in var.duties : name => concat(
      [{
        Sid      = "AllowWithinTheBoundary"
        Effect   = "Allow"
        Action   = "*"
        Resource = "*"
      }],
      [for st in local.protect[name] : st if contains(["NoOrganizationOrAccountChanges", "ProtectTheAuditTrail"], st.Sid)],
      [
        {
          Sid      = "TheStateBucketIsOffLimits"
          Effect   = "Deny"
          Action   = "s3:*"
          Resource = [local.bucket, "${local.bucket}/*"]
        },
        {
          Sid      = "NoPipelineRoles"
          Effect   = "Deny"
          Action   = ["sts:AssumeRole", "sts:AssumeRoleWithWebIdentity", "sts:AssumeRoleWithSAML", "sts:TagSession"]
          Resource = "${local.arn}:iam::*:role/terraform-*"
        },
      ],
      [for s in [{
        Sid      = "NoCentralNetworkChanges"
        Effect   = "Deny"
        Action   = local.central_network
        Resource = "*"
      }] : s if !(name == "hub")],
      [for s in [{
        Sid      = "NoChangesToTheEnvironmentsNetwork"
        Effect   = "Deny"
        Action   = local.spoke_network
        Resource = "*"
      }] : s if !(contains(["hub", "network"], name))],
      [
        {
          Sid         = "NoIamChanges"
          Effect      = "Deny"
          Action      = [for a in local.iam_writes : a if a != "iam:Pass*"]
          NotResource = ["${local.arn}:iam::*:instance-profile/eks*", "${local.arn}:iam::*:role/aws-service-role/*"]
        },
        {
          Sid         = "PassOnlyDeployedRoles"
          Effect      = "Deny"
          Action      = "iam:PassRole"
          NotResource = "${local.arn}:iam::*:role/deployed/*"
        },
        {
          Sid         = "AssumeOnlyDeployedRoles"
          Effect      = "Deny"
          Action      = "sts:AssumeRole"
          NotResource = "${local.arn}:iam::*:role/deployed/*"
        },
      ],
      [for s in [{
        Sid      = "NoUseOrDataOfOtherEnvironments"
        Effect   = "Deny"
        Action   = concat(local.uses, local.runtime_data)
        Resource = "*"
        Condition = {
          Null            = { "aws:ResourceTag/Environment" = "false" }
          StringNotEquals = { "aws:ResourceTag/Environment" = [var.environment, "shared"] }
        }
      }] : s if !local.shared],
      [
        {
          Sid       = "ChangeOnlyThisEnvironment"
          Effect    = "Deny"
          NotAction = concat(local.reads, local.uses, ["sqs:SendMessage", "sns:Publish", "logs:CreateLogStream", "logs:PutLogEvents"])
          Resource  = "*"
          Condition = {
            Null            = { "aws:ResourceTag/Environment" = "false" }
            StringNotEquals = { "aws:ResourceTag/Environment" = var.environment }
          }
        },
      ],
      [for s in [{
        Sid      = "NoBucketsOfOtherEnvironments"
        Effect   = "Deny"
        Action   = "s3:*"
        Resource = [for e in var.other_environments : "${local.arn}:s3:::${e}-*"]
      }] : s if length(var.other_environments) > 0],
      [local.create_here],
    )
  }

  regions = sort(keys(var.hub_segments))
  network_statements = concat(
    [
      {
        Sid      = "ReadTheHub"
        Effect   = "Allow"
        Action   = ["ec2:Describe*", "ec2:GetTransitGateway*", "ec2:SearchTransitGatewayRoutes", "route53:Get*", "route53:List*", "route53resolver:Get*", "route53resolver:List*", "ram:Get*", "ram:List*"]
        Resource = "*"
      },
      {
        Sid      = "AuthorizeAndAssociateItsPrivateZones"
        Effect   = "Allow"
        Action   = ["route53:CreateVPCAssociationAuthorization", "route53:DeleteVPCAssociationAuthorization", "route53:AssociateVPCWithHostedZone"]
        Resource = ["${local.arn}:route53:::hostedzone/*", "${local.arn}:ec2:*:${var.hub_account_id}:vpc/*"]
      },
    ],
    [for s in [
      {
        Sid       = "AcceptAttachmentsNotYetClaimed"
        Effect    = "Allow"
        Action    = "ec2:CreateTags"
        Resource  = [for r in local.regions : "${local.arn}:ec2:${r}:${var.hub_account_id}:transit-gateway-attachment/*"]
        Condition = { Null = { "aws:ResourceTag/Environment" = "true" }, StringEquals = { "aws:RequestTag/Environment" = var.environment } }
      },
      {
        Sid       = "AcceptAttachmentsNotYetClaimedBeforeTagging"
        Effect    = "Allow"
        Action    = "ec2:AcceptTransitGatewayVpcAttachment"
        Resource  = [for r in local.regions : "${local.arn}:ec2:${r}:${var.hub_account_id}:transit-gateway-attachment/*"]
        Condition = { Null = { "aws:ResourceTag/Environment" = "true" } }
      },
      {
        Sid    = "ManageItsOwnAttachments"
        Effect = "Allow"
        Action = [
          "ec2:RejectTransitGatewayVpcAttachment",
          "ec2:AssociateTransitGatewayRouteTable", "ec2:DisassociateTransitGatewayRouteTable",
          "ec2:EnableTransitGatewayRouteTablePropagation", "ec2:DisableTransitGatewayRouteTablePropagation",
        ]
        Resource  = [for r in local.regions : "${local.arn}:ec2:${r}:${var.hub_account_id}:transit-gateway-attachment/*"]
        Condition = { StringEquals = { "aws:ResourceTag/Environment" = var.environment } }
      },
    ] : s if !(length(local.regions) == 0)],
    [for s in [
      {
        Sid      = "ChangeOnlyTheOtherTagsOfItsOwnAttachments"
        Effect   = "Allow"
        Action   = "ec2:CreateTags"
        Resource = [for r in local.regions : "${local.arn}:ec2:${r}:${var.hub_account_id}:transit-gateway-attachment/*"]
        Condition = {
          StringEquals         = { "aws:ResourceTag/Environment" = var.environment }
          StringEqualsIfExists = { "aws:RequestTag/Environment" = var.environment }
        }
      },
      {
        Sid      = "NeverRemoveItsOwnershipTags"
        Effect   = "Allow"
        Action   = "ec2:DeleteTags"
        Resource = [for r in local.regions : "${local.arn}:ec2:${r}:${var.hub_account_id}:transit-gateway-attachment/*"]
        Condition = {
          StringEquals                   = { "aws:ResourceTag/Environment" = var.environment }
          Null                           = { "aws:TagKeys" = "false" }
          "ForAllValues:StringNotEquals" = { "aws:TagKeys" = local.ownership_keys }
        }
      },
    ] : s if length(local.regions) > 0],
    [for r in local.regions : {
      Sid       = "JoinItsOwnSegment${replace(title(replace(r, "-", " ")), " ", "")}"
      Effect    = "Allow"
      Action    = ["ec2:AssociateTransitGatewayRouteTable", "ec2:DisassociateTransitGatewayRouteTable"]
      Resource  = "${local.arn}:ec2:${r}:${var.hub_account_id}:transit-gateway-route-table/*"
      Condition = { StringEquals = { "aws:ResourceTag/Segment" = var.hub_segments[r].segment } }
    }],
    [for r in local.regions : {
      Sid       = "AnnounceToItsSegments${replace(title(replace(r, "-", " ")), " ", "")}"
      Effect    = "Allow"
      Action    = ["ec2:EnableTransitGatewayRouteTablePropagation", "ec2:DisableTransitGatewayRouteTablePropagation"]
      Resource  = "${local.arn}:ec2:${r}:${var.hub_account_id}:transit-gateway-route-table/*"
      Condition = { StringEquals = { "aws:ResourceTag/Segment" = var.hub_segments[r].propagates_to } }
    } if length(var.hub_segments[r].propagates_to) > 0],
  )

  workflow = "job_workflow_ref:${var.github_repository}/.github/workflows"
  subjects = {
    plan = [
      "repo:${var.github_repository}:environment:plan:${local.workflow}/plan.yml@refs/heads/${var.branch}",
      "repo:${var.github_repository}:environment:plan:${local.workflow}/drift.yml@refs/heads/${var.branch}",
    ]
    propose = ["repo:${var.github_repository}:ref:refs/heads/${var.branch}:${local.workflow}/apply.yml@refs/heads/${var.branch}"]
    apply   = ["repo:${var.github_repository}:environment:${var.environment}:${local.workflow}/apply.yml@refs/heads/${var.branch}"]
  }
  trust = {
    for kind, subjects in local.subjects : kind => {
      Version = "2012-10-17"
      Statement = [{
        Effect    = "Allow"
        Action    = "sts:AssumeRoleWithWebIdentity"
        Principal = { Federated = local.oidc_arn }
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:sub" = subjects
          }
        }
      }]
    }
  }

  dns_read_trust = {
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { AWS = "${local.iam}:root" }
      Condition = { ArnEquals = { "aws:PrincipalArn" = ["${local.iam}:role/terraform-plan-${var.environment}", "${local.iam}:role/terraform-propose-${var.environment}"] } }
    }]
  }

  network_trust = {
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { AWS = "${local.iam}:root" }
      Condition = { ArnEquals = { "aws:PrincipalArn" = "${local.iam}:role/terraform-apply-${var.environment}-network" } }
    }]
  }

  documents = merge(
    {
      read    = local.read
      plan    = local.plan
      propose = local.propose
    },
    { for name in keys(var.duties) : "boundary-${name}" => local.boundary_statements[name] },
    { for name in keys(var.duties) : (name) => local.apply_allow[name] },
    { for name in keys(var.duties) : "${name}-state" => local.apply_state[name] },
    { for name in keys(var.duties) : "${name}-limits" => local.apply_limits[name] },
    { for name in keys(var.duties) : "${name}-environment" => local.apply_environment[name] },
    { for name in keys(var.duties) : "${name}-ownership" => local.apply_ownership[name] },
    local.shared ? {} : { network-role = local.network_statements },
    local.shared ? {} : { dns-read-role = [{ Sid = "ReadTheZones", Effect = "Allow", Action = ["route53:Get*", "route53:List*"], Resource = "*" }] },
  )
}
