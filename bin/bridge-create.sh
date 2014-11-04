#!/usr/bin/env bash
# Create resilient OVS bridge, move IP from physical interface to bridge, attach physical interface

BRIDGE_NAME=$1
PHYSICAL_INTERFACE=$2

if [ -z "$*" ]
then
  echo "Usage: $0 <brige_name_to_create> <existing_physical_interface>"
  echo "       e.g.: $0 br-ex eth0"
  exit 1
fi

# create openvswitch bridge
if ! /usr/bin/ovs-vsctl --may-exist add-br ${BRIDGE_NAME}
then
  echo ERROR: ovs-vsctl command failed. Is openvswitch installed?
  exit 1
fi

# mv physical interface config
/bin/mv /etc/sysconfig/network-scripts/ifcfg-${PHYSICAL_INTERFACE} /etc/sysconfig/network-scripts/ifcfg-${BRIDGE_NAME}

# unset HWADDR key if exists
/bin/sed -i "/^HWADDR/d" /etc/sysconfig/network-scripts/ifcfg-${BRIDGE_NAME}

# unset UUID key if exists
/bin/sed -i "/^UUID=/d" /etc/sysconfig/network-scripts/ifcfg-${BRIDGE_NAME}

# set bridge name
## Case 1 - When ifcfg-<device> has DEVICE=<device_name>
/bin/sed -i "s/^DEVICE=.*/DEVICE=${BRIDGE_NAME}/" /etc/sysconfig/network-scripts/ifcfg-${BRIDGE_NAME}
## Case 2 - ifcfg-<device> name maybe labeled as NAME=<device_name
/bin/sed -i "s/^NAME=.*/DEVICE=${BRIDGE_NAME}/" /etc/sysconfig/network-scripts/ifcfg-${BRIDGE_NAME}

# set bridge type
/bin/sed -i s/^TYPE=.*/TYPE=OVSBridge/ /etc/sysconfig/network-scripts/ifcfg-${BRIDGE_NAME}
if ! grep -q "^TYPE=OVSBridge" /etc/sysconfig/network-scripts/ifcfg-${BRIDGE_NAME}
then
  echo ERROR: Interface TYPE was not set 
  exit 1
fi

# set bridge device type
/bin/echo -e "DEVICETYPE=ovs" >> /etc/sysconfig/network-scripts/ifcfg-${BRIDGE_NAME}

# determine if physical interface was set to dhcp
DHCP=$(grep "^BOOTPROTO=.*dhcp" /etc/sysconfig/network-scripts/ifcfg-${BRIDGE_NAME})
if [ -n "${DHCP}" ]
then
  # set bridge dhcp options for ovs if dhcp was set on physical interface
  /bin/echo -e "OVSBOOTPROTO=dhcp" >> /etc/sysconfig/network-scripts/ifcfg-${BRIDGE_NAME}
  /bin/echo -e "OVSDHCPINTERFACES=${PHYSICAL_INTERFACE}" >> /etc/sysconfig/network-scripts/ifcfg-${BRIDGE_NAME}
fi

# create new physical interface config
cat > /etc/sysconfig/network-scripts/ifcfg-${PHYSICAL_INTERFACE} <<EOF
DEVICE=$PHYSICAL_INTERFACE
DEVICETYPE=ovs
TYPE=OVSPort
BOOTPROTO=none
OVS_BRIDGE=${BRIDGE_NAME}
ONBOOT=yes
EOF

# switch on bridge and restart network - atomic operation
/usr/bin/ovs-vsctl --may-exist add-port ${BRIDGE_NAME} $PHYSICAL_INTERFACE; service network restart  
