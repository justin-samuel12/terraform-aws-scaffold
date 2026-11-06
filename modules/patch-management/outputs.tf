output "patch_group" {
  description = "The tag value instances carry to be patched: PatchGroup = this."
  value       = var.environment
}

output "baselines" {
  description = "Baseline name -> its ID."
  value       = { for name, b in aws_ssm_patch_baseline.baselines : name => b.id }
}
