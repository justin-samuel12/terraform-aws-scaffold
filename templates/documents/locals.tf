locals {
  config_dir = coalesce(var.config_dir, "${path.root}/config")
  found      = { for path in fileset(local.config_dir, "**/*.yml") : trimsuffix(basename(path), ".yml") => path... }
  files      = { for name, paths in local.found : name => try(yamldecode(file("${local.config_dir}/${sort(paths)[0]}")), null) }
  file_keys  = ["document_type", "content"]

  problems = concat(
    [for name, paths in local.found : "${name}.yml is in more than one folder (${join(", ", sort(paths))}); a document's name is its file's, so it must be unique" if length(paths) > 1],
    [for name, f in local.files : "${name}.yml: keys are ${join(", ", local.file_keys)}, as aws_ssm_document takes them, and both are needed" if !(length(try(keys(f), [])) == 2 && alltrue([for k in try(keys(f), []) : contains(local.file_keys, k)]))],
  )

  documents = { for name, f in local.files : name => { type = tostring(f.document_type), content = f.content } if length(local.problems) == 0 }
}
