locals {
  config_dir = coalesce(var.config_dir, "${path.root}/config")
  paths      = [for path in fileset(local.config_dir, "**/*.yml") : path]
  found = {
    for path in local.paths : trimsuffix(basename(path), ".yml") => path... if startswith(path, "distribution/")
  }
  files     = { for name, paths in local.found : name => yamldecode(file("${local.config_dir}/${sort(paths)[0]}")) }
  web_acls  = toset([for path in local.paths : trimsuffix(basename(path), ".yml") if startswith(path, "web-acl/")])
  policy_id = "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"

  file_keys        = ["aliases", "origin", "default_cache_behavior", "price_class", "viewer_certificate", "web_acl_id"]
  origin_keys      = ["origin_id", "domain_name"]
  cache_keys       = ["target_origin_id", "viewer_protocol_policy", "allowed_methods", "cached_methods", "compress", "cache_policy_id", "response_headers_policy_id"]
  certificate_keys = ["acm_certificate_arn", "ssl_support_method", "minimum_protocol_version", "cloudfront_default_certificate"]

  origins = { for name, f in local.files : name => try([for o in f.origin : o if !can(keys(f.origin))], []) }

  distributions = {
    for name, f in local.files : name => {
      aliases = try([for a in f.aliases : tostring(a)], [])
      origin = [
        for o in local.origins[name] : {
          origin_id   = try(tostring(o.origin_id), "")
          domain_name = try(tostring(o.domain_name), "")
        }
      ]
      default_cache_behavior = {
        target_origin_id           = try(tostring(f.default_cache_behavior.target_origin_id), "")
        viewer_protocol_policy     = try(tostring(f.default_cache_behavior.viewer_protocol_policy), "")
        allowed_methods            = try([for m in f.default_cache_behavior.allowed_methods : tostring(m)], [])
        cached_methods             = try([for m in f.default_cache_behavior.cached_methods : tostring(m)], [])
        compress                   = try(tobool(f.default_cache_behavior.compress), null)
        cache_policy_id            = try(tostring(f.default_cache_behavior.cache_policy_id), "")
        response_headers_policy_id = try(tostring(f.default_cache_behavior.response_headers_policy_id), null)
      }
      price_class = try(tostring(f.price_class), "")
      viewer_certificate = {
        acm_certificate_arn            = try(tostring(f.viewer_certificate.acm_certificate_arn), null)
        ssl_support_method             = try(tostring(f.viewer_certificate.ssl_support_method), null)
        minimum_protocol_version       = try(tostring(f.viewer_certificate.minimum_protocol_version), null)
        cloudfront_default_certificate = try(tobool(f.viewer_certificate.cloudfront_default_certificate), null)
      }
      web_acl_id = try(tostring(f.web_acl_id), null)
    }
  }

  bucket_lookups       = toset(flatten([for d in local.distributions : [for o in d.origin : o.domain_name if o.domain_name != "" && !endswith(o.domain_name, ".amazonaws.com")]]))
  certificate_lookups  = toset([for d in local.distributions : d.viewer_certificate.acm_certificate_arn if d.viewer_certificate.acm_certificate_arn != null && !startswith(coalesce(d.viewer_certificate.acm_certificate_arn, "arn:"), "arn:")])
  cache_policy_lookups = toset([for d in local.distributions : d.default_cache_behavior.cache_policy_id if d.default_cache_behavior.cache_policy_id != "" && !can(regex(local.policy_id, d.default_cache_behavior.cache_policy_id))])
  headers_lookups      = toset([for d in local.distributions : d.default_cache_behavior.response_headers_policy_id if d.default_cache_behavior.response_headers_policy_id != null && !can(regex(local.policy_id, coalesce(d.default_cache_behavior.response_headers_policy_id, "-")))])

  problems = concat(
    [for path in local.paths : "${path}: a distribution's file is in distribution/, a web ACL's in web-acl/" if !startswith(path, "distribution/") && !startswith(path, "web-acl/")],
    [for name, paths in local.found : "${name}.yml is in more than one folder (${join(", ", sort(paths))}); a distribution's name is its file's, so it must be unique" if length(paths) > 1],
    [for name, f in local.files : "${name}.yml: keys are ${join(", ", local.file_keys)}, as aws_cloudfront_distribution takes them" if !can(keys(f)) || !alltrue([for k in try(keys(f), []) : contains(local.file_keys, k)])],
    [for name, f in local.files : "${name}.yml: origin is a list of origins, each taking ${join(", ", local.origin_keys)}" if !can([for o in f.origin : o]) || can(keys(f.origin)) || !alltrue([for o in local.origins[name] : can(keys(o)) && try(jsonencode(sort(keys(o))) == jsonencode(sort(local.origin_keys)), false)])],
    [for name, f in local.files : "${name}.yml: default_cache_behavior takes ${join(", ", local.cache_keys)}; all but response_headers_policy_id are needed" if !can(keys(f.default_cache_behavior)) || !alltrue([for k in try(keys(f.default_cache_behavior), []) : contains(local.cache_keys, k)]) || !alltrue([for k in local.cache_keys : k == "response_headers_policy_id" || contains(try(keys(f.default_cache_behavior), []), k)])],
    [for name, f in local.files : "${name}.yml: viewer_certificate takes ${join(", ", local.certificate_keys)}" if !can(keys(f.viewer_certificate)) || !alltrue([for k in try(keys(f.viewer_certificate), []) : contains(local.certificate_keys, k)])],
    [for name, d in local.distributions : "${name}.yml: price_class is needed (PriceClass_100, PriceClass_200 or PriceClass_All)" if d.price_class == ""],
    [for name, d in local.distributions : "${name}.yml: web_acl_id ${d.web_acl_id} is not a web ACL in this stack (a file named web-acl/${d.web_acl_id}.yml), nor an ARN" if d.web_acl_id != null && !startswith(coalesce(d.web_acl_id, "arn:"), "arn:") && !contains(local.web_acls, coalesce(d.web_acl_id, "-"))],
  )

  resolved = {
    for name, d in local.distributions : name => merge(d, {
      origin = [
        for o in d.origin : merge(o, {
          domain_name = endswith(o.domain_name, ".amazonaws.com") ? o.domain_name : try(data.aws_s3_bucket.origins[o.domain_name].bucket_regional_domain_name, o.domain_name)
        })
      ]
      default_cache_behavior = merge(d.default_cache_behavior, {
        cache_policy_id            = can(regex(local.policy_id, d.default_cache_behavior.cache_policy_id)) ? d.default_cache_behavior.cache_policy_id : try(data.aws_cloudfront_cache_policy.policies[d.default_cache_behavior.cache_policy_id].id, "")
        response_headers_policy_id = d.default_cache_behavior.response_headers_policy_id == null ? null : can(regex(local.policy_id, d.default_cache_behavior.response_headers_policy_id)) ? d.default_cache_behavior.response_headers_policy_id : try(data.aws_cloudfront_response_headers_policy.policies[d.default_cache_behavior.response_headers_policy_id].id, null)
      })
      viewer_certificate = merge(d.viewer_certificate, {
        acm_certificate_arn = d.viewer_certificate.acm_certificate_arn == null ? null : startswith(d.viewer_certificate.acm_certificate_arn, "arn:") ? d.viewer_certificate.acm_certificate_arn : try(data.aws_acm_certificate.certificates[d.viewer_certificate.acm_certificate_arn].arn, null)
      })
      web_acl_id = d.web_acl_id == null ? null : startswith(d.web_acl_id, "arn:") ? d.web_acl_id : try(module.web_acls.arns[d.web_acl_id], null)
    })
  }
}
