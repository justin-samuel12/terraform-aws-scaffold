#!/bin/bash
set -Eeuo pipefail
exec > >(tee -a /var/log/first-boot.log) 2>&1
trap 'echo "first boot failed at line ${LINENO}"' ERR
echo "first boot: $(date -Is)"

metadata() {
    curl -fsS --connect-timeout 3 --max-time 10 --retry 3 -H "X-aws-ec2-metadata-token: ${token}" "http://169.254.169.254/latest/meta-data/$1"
}
token=$(curl -fsS --connect-timeout 3 --max-time 10 --retry 3 -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 300')
name=$(metadata tags/instance/Server)
[[ "${name}" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,62}$ ]] || { echo "the Server tag '${name}' is not a host name"; exit 1; }

printf 'preserve_hostname: true\n' > /etc/cloud/cloud.cfg.d/99-preserve-hostname.cfg
hostnamectl set-hostname "${name}"
sed -i '/^127\.0\.1\.1[[:space:]]/d' /etc/hosts
echo "127.0.1.1 ${name}" >> /etc/hosts

for unit in docker codedeploy-agent amazon-cloudwatch-agent; do
    if systemctl list-unit-files "${unit}.service" --no-legend | grep -q .; then
        systemctl enable --now "${unit}"
        echo "started ${unit}"
    fi
done
echo "first boot done: $(date -Is)"
