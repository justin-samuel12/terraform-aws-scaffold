output "domain_join" {
  description = "The join document, the join secret (whose value a person sets, and which the joining servers' role reads) and association name -> id."
  value = {
    document_name   = module.domain_join.document_name
    secret_arn      = module.domain_join.secret_arn
    association_ids = module.domain_join.association_ids
  }

  precondition {
    condition     = length(local.problems) == 0
    error_message = "The association files are not usable: ${join("; ", local.problems)}."
  }
}
