#cloud-config
hostname: openstack
password: ubuntu
chpasswd: { expire: False }
ssh_pwauth: True
write_files:
  - content: |
      net.ipv4.ip_forward=1
      net.ipv4.conf.default.rp_filter=0
      net.ipv4.conf.all.rp_filter=0
    path: /etc/sysctl.d/devstack.conf
  - content: |
      #!/bin/bash

      set -o errexit -o nounset -o pipefail

      # Install kvm / ensure nested virtualization
      sudo apt-get update && sudo apt-get install qemu-kvm jq net-tools -y
      kvm-ok
      sudo modprobe kvm-intel

      # from https://raw.githubusercontent.com/openstack/octavia/master/devstack/contrib/new-octavia-devstack.sh
      git clone -b stable/${OPENSTACK_RELEASE} https://github.com/openstack/devstack.git /tmp/devstack

      cat <<EOF > /tmp/devstack/localrc
      GIT_BASE=https://github.com

      # Neutron
      enable_plugin neutron https://github.com/openstack/neutron stable/${OPENSTACK_RELEASE}

      # Octavia
      enable_plugin octavia https://github.com/openstack/octavia stable/${OPENSTACK_RELEASE}
      enable_plugin octavia-dashboard https://github.com/openstack/octavia-dashboard stable/${OPENSTACK_RELEASE}
      #LIBS_FROM_GIT+=python-octaviaclient

      # Cinder
      enable_plugin cinderlib https://github.com/openstack/cinderlib stable/${OPENSTACK_RELEASE}

      KEYSTONE_TOKEN_FORMAT=fernet

      SERVICE_TIMEOUT=240

      DATABASE_PASSWORD=secretdatabase
      RABBIT_PASSWORD=secretrabbit
      ADMIN_PASSWORD=secretadmin
      SERVICE_PASSWORD=secretservice
      SERVICE_TOKEN=111222333444
      # Enable Logging
      LOGFILE=/opt/stack/logs/stack.sh.log
      VERBOSE=True
      LOG_COLOR=True

      # Pre-requisite
      ENABLED_SERVICES=key,rabbit,mysql
      # Nova
      ENABLED_SERVICES+=,n-api,n-obj,n-cpu,n-cond,n-sch,n-novnc,n-api-meta
      # Placement service needed for Nova
      ENABLED_SERVICES+=,placement-api,placement-client
      # Glance
      ENABLED_SERVICES+=,g-api,g-reg

      # Octavia-Neutron
      ENABLED_SERVICES+=,neutron-api,neutron-agent,neutron-dhcp,neutron-l3
      ENABLED_SERVICES+=,neutron-metadata-agent,neutron-qos
      # Octavia
      ENABLED_SERVICES+=,octavia,o-api,o-cw,o-hm,o-hk,o-da

      # Horizon (enable for manual tests)
      #ENABLED_SERVICES+=,horizon

      # Cinder
      ENABLED_SERVICES+=,c-sch,c-api,c-vol

      LIBVIRT_TYPE=kvm

      # Don't download default images, just our test images
      DOWNLOAD_DEFAULT_IMAGES=False
      IMAGE_URLS="https://github.com/kubernetes-sigs/cluster-api-provider-openstack/releases/download/v0.3.0/ubuntu-1910-kube-v1.17.3.qcow2,"
      IMAGE_URLS+="http://download.cirros-cloud.net/0.5.1/cirros-0.5.1-x86_64-disk.img"
      EOF

      # Create the stack user
      /tmp/devstack/tools/create-stack-user.sh

      # Move everything into place (/opt/stack is the $HOME folder of the stack user)
      mv /tmp/devstack /opt/stack/
      chown -R stack:stack /opt/stack/devstack/

      # Stack that stack!
      su - stack -c /opt/stack/devstack/stack.sh

      # Add environment variables for auth/endpoints
      echo 'source /opt/stack/devstack/openrc admin admin' >> /opt/stack/.bashrc

      sudo iptables -t nat -I POSTROUTING -o ens4 -s 172.24.4.0/24 -j MASQUERADE
      sudo iptables -I FORWARD -s 172.24.4.0/24 -j ACCEPT

    path: /root/devstack.sh
    permissions: '0777'
runcmd:
  - sysctl -p /etc/sysctl.d/devstack.conf
  - /root/devstack.sh
final_message: "The system is finally up, after $UPTIME seconds"
