#!/bin/bash
set -euo pipefail
token=$(curl -sX PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 300')
name=$(curl -s -H "X-aws-ec2-metadata-token: ${token}" http://169.254.169.254/latest/meta-data/tags/instance/Name)
hostnamectl set-hostname "${name}"
systemctl enable --now codedeploy-agent amazon-cloudwatch-agent || true
