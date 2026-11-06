data "aws_default_tags" "current" {}

data "aws_ami" "image" {
  filter {
    name   = "image-id"
    values = [var.image_id]
  }
}
