#!/bin/bash
set -Eeuo pipefail
exec > >(tee -a /var/log/first-boot.log) 2>&1
trap 'echo "first boot failed at line ${LINENO}"' ERR
echo "first boot: $(date -Is)"

[[ "${EUID}" -eq 0 ]] || { echo "first boot must run as root"; exit 1; }
export DEBIAN_FRONTEND=noninteractive

metadata() {
    curl -fsS --connect-timeout 3 --max-time 10 --retry 3 -H "X-aws-ec2-metadata-token: ${token}" "http://169.254.169.254/latest/meta-data/$1"
}
token=$(curl -fsS --connect-timeout 3 --max-time 10 --retry 3 -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 300')
name=$(metadata tags/instance/Server)
[[ "${name}" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,62}$ ]] || { echo "the Server tag '${name}' is not a host name"; exit 1; }
echo "instance: $(metadata instance-id) | zone: $(metadata placement/availability-zone) | server: ${name}"

printf 'preserve_hostname: true\n' > /etc/cloud/cloud.cfg.d/99-preserve-hostname.cfg
hostnamectl set-hostname "${name}"
sed -i '/^127\.0\.1\.1[[:space:]]/d' /etc/hosts
echo "127.0.1.1 ${name}" >> /etc/hosts

update_packages() {
    local file
    local apt_options=(-o DPkg::Lock::Timeout=300 -o Acquire::Retries=3)
    while IFS= read -r file; do
        mv "${file}" "${file}.disabled"
        echo "disabled the Yarn repository in ${file}"
    done < <(grep -rlF dl.yarnpkg.com/debian /etc/apt/sources.list.d || true)
    apt-get "${apt_options[@]}" update &&
        apt-get -y "${apt_options[@]}" -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold dist-upgrade &&
        apt-get -y "${apt_options[@]}" install ca-certificates curl wget jq unzip zip gnupg lsb-release dnsutils iputils-ping traceroute net-tools tcpdump openssl vim htop git
}
if ! update_packages; then
    echo "first boot: updates failed, the patch window will catch up"
fi

timedatectl status || true
if systemctl is-active --quiet snap.amazon-ssm-agent.amazon-ssm-agent.service || systemctl is-active --quiet amazon-ssm-agent.service; then
    echo "SSM agent running"
else
    echo "SSM agent not running"
fi

units=()
for unit in codedeploy-agent amazon-cloudwatch-agent; do
    if systemctl list-unit-files "${unit}.service" --no-legend | grep -q .; then
        systemctl enable "${unit}"
        units+=("${unit}")
    fi
done

echo "kernel: $(uname -r)"
if [[ -f /var/run/reboot-required ]]; then
    echo "first boot done, restarting in a minute: $(date -Is)"
    shutdown -r +1 "first boot updates"
    exit 0
fi

for unit in "${units[@]}"; do
    systemctl start "${unit}"
    echo "started ${unit}"
done
echo "first boot done: $(date -Is)"
