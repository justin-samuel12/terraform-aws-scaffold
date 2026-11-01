module "ssm_document" {
  source = "../../modules/ssm-document"

  documents = { for name, d in local.documents : name => d if length(local.problems) == 0 }
}
