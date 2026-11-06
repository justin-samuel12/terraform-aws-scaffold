module "ssm_document" {
  source = "../../modules/ssm-document"

  documents = local.documents
}
