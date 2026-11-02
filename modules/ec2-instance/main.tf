resource "aws_instance" "servers" {
  for_each = var.members

  ami                         = var.image_id
  instance_type               = each.value.instance_type
  subnet_id                   = each.value.subnet_id
  private_ip                  = each.value.private_ip
  secondary_private_ips       = length(each.value.secondary_ips) > 0 ? each.value.secondary_ips : null
  vpc_security_group_ids      = var.security_group_ids
  iam_instance_profile        = var.instance_profile
  associate_public_ip_address = false
  monitoring                  = true
  ebs_optimized               = true
  user_data                   = var.user_data
  disable_api_termination     = true
  disable_api_stop            = false
  force_destroy               = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  maintenance_options {
    auto_recovery = "default"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_size
    encrypted   = true
    kms_key_id  = var.kms_key_arn
    tags        = merge(local.tags, { Name = "${each.key}-root" })
  }

  tags = merge(local.tags, { Name = each.key, Subnet = each.value.subnet })

  provisioner "local-exec" {
    when       = destroy
    on_failure = continue
    command    = "aws ec2 modify-instance-attribute --region ${split(":", self.arn)[3]} --instance-id ${self.id} --no-disable-api-termination && aws ec2 terminate-instances --region ${split(":", self.arn)[3]} --instance-ids ${self.id} --skip-os-shutdown --output text --query 'TerminatingInstances[].CurrentState.Name'"
  }

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

resource "aws_ebs_volume" "volumes" {
  for_each = local.volumes

  availability_zone = aws_instance.servers[each.value.member].availability_zone
  type              = "gp3"
  size              = each.value.size
  iops              = each.value.iops
  throughput        = each.value.throughput
  encrypted         = true
  kms_key_id        = var.kms_key_arn

  tags = merge(local.tags, { Name = "${each.value.member}-${each.value.name}" })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_volume_attachment" "volumes" {
  for_each = local.volumes

  device_name = each.value.device
  volume_id   = aws_ebs_volume.volumes[each.key].id
  instance_id = aws_instance.servers[each.value.member].id
}

resource "aws_lb_target_group_attachment" "registrations" {
  for_each = local.registrations

  target_group_arn = each.value.arn
  target_id        = aws_instance.servers[each.value.member].id
  port             = each.value.port
}
