# This stack is templates/cloudfront for its environment and region -- docs/architecture.md.
module "cloudfront" {
  source = "../../../../templates/cloudfront"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}
