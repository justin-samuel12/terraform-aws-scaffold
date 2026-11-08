module "policies" {
  source = "../.."

  environment        = var.environment
  account_id         = var.environment == "shared" ? "111111111111" : "222222222222"
  hub_account_id     = "111111111111"
  state_bucket       = "example-terraform-state"
  github_repository  = "example-org/infrastructure"
  branch             = "main"
  other_environments = [for e in ["operations", "production", "shared", "staging"] : e if e != var.environment]
  hub_segments       = var.environment == "shared" ? {} : { "us-west-2" = { segment = "standard", propagates_to = ["standard", "shared"] } }
  duties             = { for name, d in yamldecode(file("${path.module}/../../../../templates/duties.yml")) : name => d if contains([var.environment == "shared" ? "shared" : "spokes", "any"], d.environments) && name != "pipeline" }
}
