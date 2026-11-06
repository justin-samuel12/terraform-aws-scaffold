locals {
  config_dir = coalesce(var.config_dir, "${path.root}/config")
  found = {
    for path in fileset(local.config_dir, "**/*.yml") : trimsuffix(basename(path), ".yml") => path...
  }
  files = { for name, paths in local.found : name => yamldecode(file("${local.config_dir}/${sort(paths)[0]}")) }

  file_keys      = ["domain_name", "subject_alternative_names", "validation_method", "key_algorithm", "tags", "route53_record"]
  key_algorithms = ["RSA_2048", "RSA_3072", "RSA_4096", "EC_prime256v1", "EC_secp384r1", "EC_secp521r1"]

  parsed = {
    for name, f in local.files : name => {
      domain_name               = try(tostring(f.domain_name), "")
      subject_alternative_names = try(f.subject_alternative_names, null) == null ? [] : try([for d in tolist(f.subject_alternative_names) : tostring(d)], [])
      validation_method         = try(tostring(f.validation_method), "")
      key_algorithm             = try(tostring(f.key_algorithm), "")
      tags                      = try(tomap(f.tags), {})
      validation_zone           = try(tostring(f.route53_record.zone_id), "")
    }
  }

  problems = concat(
    [for name, paths in local.found : "${name}.yml is in more than one folder (${join(", ", sort(paths))}); a certificate's name is its file's, so it must be unique" if length(paths) > 1],
    [for name, f in local.files : "${name}.yml: keys are ${join(", ", local.file_keys)}: aws_acm_certificate's arguments and the public zone its validation records go in" if !can(keys(f)) || !alltrue([for k in try(keys(f), []) : contains(local.file_keys, k)])],
    [for name, c in local.parsed : "${name}.yml: domain_name is required" if c.domain_name == ""],
    [for name, c in local.parsed : "${name}.yml: validation_method is DNS, the only method that renews by itself" if c.validation_method != "DNS"],
    [for name, c in local.parsed : "${name}.yml: key_algorithm is one of ${join(", ", local.key_algorithms)}" if !contains(local.key_algorithms, c.key_algorithm)],
    [for name, c in local.parsed : "${name}.yml: route53_record.zone_id is required: the public hosted zone, such as example.com, that proves every name on the certificate" if c.validation_zone == ""],
    flatten([for name, c in local.parsed : [for d in concat([c.domain_name], c.subject_alternative_names) : "${name}.yml: ${d} is not in route53_record.zone_id ${c.validation_zone}" if c.validation_zone != "" && d != "" && d != c.validation_zone && !endswith(d, ".${c.validation_zone}")]]),
  )

  certificates = { for name, c in local.parsed : name => c if length(local.problems) == 0 }
}
