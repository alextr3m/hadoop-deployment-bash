#!/bin/bash
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Copyright Clairvoyant 2017

DATA="net.core.netdev_max_backlog = 250000
net.core.optmem_max = 4194304
net.core.rmem_default = 4194304
net.core.rmem_max = 4194304
net.core.wmem_default = 4194304
net.core.wmem_max = 4194304
net.ipv4.tcp_adv_win_scale = 1
net.ipv4.tcp_low_latency = 1
net.ipv4.tcp_rmem = 4096 87380 4194304
net.ipv4.tcp_sack = 1
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_wmem = 4096 65536 4194304"

# Function to discover basic OS details.
discover_os () {
  if command -v lsb_release >/dev/null; then
    # CentOS, Ubuntu
    OS=$(lsb_release -is)
    # 7.2.1511, 14.04
    OSVER=$(lsb_release -rs)
    # 7, 14
    OSREL=$(echo "$OSVER" | awk -F. '{print $1}')
    # trusty, wheezy, Final
    OSNAME=$(lsb_release -cs)
  else
    if [ -f /etc/redhat-release ]; then
      if [ -f /etc/centos-release ]; then
        OS=CentOS
      else
        OS=RedHatEnterpriseServer
      fi
      OSVER=$(rpm -qf /etc/redhat-release --qf="%{VERSION}.%{RELEASE}\n")
      OSREL=$(rpm -qf /etc/redhat-release --qf="%{VERSION}\n" | awk -F. '{print $1}')
    fi
  fi
}

_sysctld () {
  FILE=/etc/sysctl.d/clairvoyant-network.conf

  install -m 0644 -o root -g root /dev/null "$FILE"
  cat <<EOF >"${FILE}"
# Tuning for Hadoop installation. CLAIRVOYANT
$DATA
EOF
}

# Check to see if we are on a supported OS.
discover_os
if [ "$OS" != RedHatEnterpriseServer ] && [ "$OS" != CentOS ] && [ "$OS" != Debian ] && [ "$OS" != Ubuntu ]; then
  echo "ERROR: Unsupported OS."
  exit 3
fi

FILE=/etc/sysctl.conf

if [ "$OS" == RedHatEnterpriseServer ] || [ "$OS" == CentOS ]; then
  if [ ! -d /etc/sysctl.d ]; then
    for PARAM in $(echo "$DATA" | awk '{print $1}'); do
      VAL=$(echo "$DATA" | awk -F= "/^${PARAM} = /{print \$2}" | sed -e 's|^ ||')
      if grep -q "$PARAM" "$FILE"; then
        sed -i -e "/^${PARAM}/s|=.*|= $VAL|" "$FILE"
      else
        echo "${PARAM} = ${VAL}" >>"${FILE}"
      fi
    done
  else
    for PARAM in $(echo "$DATA" | awk '{print $1}'); do
      if grep -q "$PARAM" "$FILE"; then
        sed -i -e "/^${PARAM}/d" "$FILE"
      fi
    done
    _sysctld
  fi
elif [ "$OS" == Debian ] || [ "$OS" == Ubuntu ]; then
  for PARAM in $(echo "$DATA" | awk '{print $1}'); do
    if grep -q "$PARAM" "$FILE"; then
      sed -i -e "/^${PARAM}/d" "$FILE"
    fi
  done
  _sysctld
fi

echo "** Applying Kernel parameters."
sysctl -p "$FILE"

