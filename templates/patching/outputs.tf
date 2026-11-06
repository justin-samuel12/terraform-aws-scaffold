output "patch_group" {
  description = "The tag instances carry to be patched: PatchGroup = this."
  value       = module.patch_management.patch_group

  precondition {
    condition     = local.ready
    error_message = "The patching files are not usable: ${join("; ", local.problems)}."
  }
}

output "baselines" {
  description = "Baseline name -> its ID."
  value       = module.patch_management.baselines
}
