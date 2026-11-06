output "files" {
  description = "Every file by name: those on a blueprint expanded into ordinary files of the stack, the rest as they were."
  value       = merge(var.files, local.expanded)
}

output "refs" {
  description = "File name -> the blueprint it names (<name>/v<n>)."
  value       = local.refs
}

output "blueprints" {
  description = "Blueprint (<name>/v<n>) -> its contents, null where it is missing or unreadable."
  value       = local.blueprints
}

output "problems" {
  description = "What is wrong with the files on blueprints, or the blueprints they name; empty when all are usable."
  value       = local.problems
}
