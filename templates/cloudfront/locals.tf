locals {
  config_dir = coalesce(var.config_dir, path.root)
  files      = { for name in fileset(local.config_dir, "*.yml") : trimsuffix(name, ".yml") => yamldecode(file("${local.config_dir}/${name}")) }

  distributions = {
    for name, f in local.files : name => {
      aliases       = try(tolist(f.aliases), [])
      origin_bucket = f.origin_bucket
      certificate   = try(f.certificate, null)
      waf           = try(f.waf, false)
      price_class   = try(f.price_class, "PriceClass_100")
    }
  }

  account_id = data.aws_caller_identity.current.account_id
}
