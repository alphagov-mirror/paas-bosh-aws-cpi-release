#!/usr/bin/env bash

set -e

source bosh-cpi-release/ci/tasks/utils.sh

check_param aws_access_key_id
check_param aws_secret_access_key
check_param region_name
check_param stemcell_name

source /etc/profile.d/chruby.sh
chruby 2.1.2

export AWS_ACCESS_KEY_ID=${aws_access_key_id}
export AWS_SECRET_ACCESS_KEY=${aws_secret_access_key}
export AWS_DEFAULT_REGION=${region_name}

cpi_release_name="bosh-aws-cpi"
stack_name="aws-cpi-stack"
stack_info=$(get_stack_info $stack_name)

DIRECTOR=$(get_stack_info_of "${stack_info}" "BoshIntegrationEIP")
SUBNET_ID=$(get_stack_info_of "${stack_info}" "BoshIntegrationSubnetID")
AVAILABILITY_ZONE=$(get_stack_info_of "${stack_info}" "BoshIntegrationAvailabilityZone")
sg_id=$(get_stack_info_of "${stack_info}" "SecurityGroupID")
NETWORK_CIDR=$(get_stack_info_of "${stack_info}" "BoshIntegrationCIDR")
NETWORK_GATEWAY=$(get_stack_info_of "${stack_info}" "BoshIntegrationGateway")
NETWORK_RESERVED_RANGE=$(get_stack_info_of "${stack_info}" "BoshIntegrationReservedRange")
SECURITY_GROUP_NAME=$(aws ec2 describe-security-groups --group-ids ${sg_id} | jq -r '.SecurityGroups[] .GroupName')

bosh -n target $DIRECTOR

bosh login admin admin

cat > "dummy-manifest.yml" <<EOF
---
name: dummy
director_uuid: $(bosh status --uuid)

releases:
- name: dummy
  version: latest

compilation:
  reuse_compilation_vms: true
  workers: 1
  network: private
  cloud_properties:
    instance_type: m3.medium
    availability_zone: ${AVAILABILITY_ZONE}

update:
  canaries: 1
  canary_watch_time: 30000-240000
  update_watch_time: 30000-600000
  max_in_flight: 3

resource_pools:
- name: default
  stemcell:
    name: ${stemcell_name}
    version: latest
  network: private
  size: 1
  cloud_properties:
    instance_type: m3.medium
    availability_zone: ${AVAILABILITY_ZONE}

networks:
- name: private
  type: manual
  subnets:
  - range:    ${NETWORK_CIDR}
    gateway:  ${NETWORK_GATEWAY}
    dns:      ['8.8.8.8']
    reserved: [${NETWORK_RESERVED_RANGE}]
    cloud_properties: {subnet: ${SUBNET_ID}}

jobs:
- name: dummy
  template: dummy
  instances: 1
  resource_pool: default
  networks:
  - name : private
    default: [dns, gateway]
EOF

bosh upload stemcell stemcell/stemcell.tgz

bosh upload release dummy-release/dummy.tgz

bosh -d dummy-manifest.yml -n deploy

bosh -n delete deployment dummy

bosh -n cleanup --all
