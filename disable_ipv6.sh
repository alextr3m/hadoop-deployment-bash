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
# Copyright Clairvoyant 2016

DATE=`date +'%Y%m%d%H%M%S'`

# Function to discover basic OS details.
discover_os () {
  if command -v lsb_release >/dev/null; then
    # CentOS, Ubuntu
    OS=`lsb_release -is`
    # 7.2.1511, 14.04
    OSVER=`lsb_release -rs`
    # 7, 14
    OSREL=`echo $OSVER | awk -F. '{print $1}'`
    # trusty, wheezy, Final
    OSNAME=`lsb_release -cs`
  else
    if [ -f /etc/redhat-release ]; then
      if [ -f /etc/centos-release ]; then
        OS=CentOS
      else
        OS=RedHatEnterpriseServer
      fi
      OSVER=`rpm -qf /etc/redhat-release --qf="%{VERSION}.%{RELEASE}\n"`
      OSREL=`rpm -qf /etc/redhat-release --qf="%{VERSION}\n" | awk -F. '{print $1}'`
    fi
  fi
}

# Check to see if we are on a supported OS.
discover_os
if [ "$OS" != RedHatEnterpriseServer -a "$OS" != CentOS -a "$OS" != Debian -a "$OS" != Ubuntu ]; then
  echo "ERROR: Unsupported OS."
  exit 3
fi

if [ "$OS" == RedHatEnterpriseServer -o "$OS" == CentOS ]; then
  echo "** Disabling IPv6 kernel configuration..."
  # https://access.redhat.com/solutions/8709
  # https://wiki.centos.org/FAQ/CentOS7#head-8984faf811faccca74c7bcdd74de7467f2fcd8ee
  #sysctl -w net.ipv6.conf.all.disable_ipv6=1
  #sysctl -w net.ipv6.conf.default.disable_ipv6=1

  if [ -d /etc/sysctl.d ]; then
    if grep -q net.ipv6.conf.all.disable_ipv6 /etc/sysctl.conf; then
      sed -i -e '/^net.ipv6.conf.all.disable_ipv6/d' /etc/sysctl.conf
    fi
    if grep -q net.ipv6.conf.default.disable_ipv6 /etc/sysctl.conf; then
      sed -i -e '/^net.ipv6.conf.default.disable_ipv6/d' /etc/sysctl.conf
    fi
    echo "# Tuning for Hadoop installation." >/etc/sysctl.d/cloudera-ipv6.conf
    echo "# CLAIRVOYANT" >>/etc/sysctl.d/cloudera-ipv6.conf
    echo "net.ipv6.conf.all.disable_ipv6 = 1" >>/etc/sysctl.d/cloudera-ipv6.conf
    echo "net.ipv6.conf.default.disable_ipv6 = 1" >>/etc/sysctl.d/cloudera-ipv6.conf
    chown root:root /etc/sysctl.d/cloudera-ipv6.conf
    chmod 0644 /etc/sysctl.d/cloudera-ipv6.conf
    sysctl -p /etc/sysctl.d/cloudera-ipv6.conf
  else
    if grep -q net.ipv6.conf.all.disable_ipv6 /etc/sysctl.conf; then
      sed -i -e "/^net.ipv6.conf.all.disable_ipv6/s|=.*|= 1|" /etc/sysctl.conf
    else
      echo "net.ipv6.conf.all.disable_ipv6 = 1" >>/etc/sysctl.conf
    fi
    if grep -q net.ipv6.conf.default.disable_ipv6 /etc/sysctl.conf; then
      sed -i -e "/^net.ipv6.conf.default.disable_ipv6/s|=.*|= 1|" /etc/sysctl.conf
    else
      echo "net.ipv6.conf.default.disable_ipv6 = 1" >>/etc/sysctl.conf
    fi
    sysctl -p /etc/sysctl.conf
  fi

  echo "** Disabling IPv6 kernel module..."
  cat <<EOF >/etc/modprobe.d/cloudera-ipv6.conf
# CLAIRVOYANT
# Tuning for Hadoop installation.
options ipv6 disable=1
EOF
  chown root:root /etc/modprobe.d/cloudera-ipv6.conf
  chmod 0644 /etc/modprobe.d/cloudera-ipv6.conf

  echo "** Disabling IPv6 in /etc/ssh/sshd_config..."
  cp -p /etc/ssh/sshd_config /etc/ssh/sshd_config.${DATE}
  sed -e '/# CLAIRVOYANT$/d' \
      -e '/^AddressFamily /d' \
      -e '/^ListenAddress /d' \
      -i /etc/ssh/sshd_config
#mja needs work : assumes 0.0.0.0
  cat <<EOF >>/etc/ssh/sshd_config
# Hadoop: Disable IPv6 support # CLAIRVOYANT
AddressFamily inet             # CLAIRVOYANT
ListenAddress 0.0.0.0          # CLAIRVOYANT
# Hadoop: Disable IPv6 support # CLAIRVOYANT
EOF
  service sshd restart

  if rpm -q postfix >/dev/null; then
    echo "** Disabling IPv6 in Postfix..."
    cp -p /etc/postfix/main.cf /etc/postfix/main.cf.${DATE}
#mja needs work : assumes 127.0.0.1
    postconf inet_interfaces
    postconf -e inet_interfaces=127.0.0.1
    service postfix condrestart
  fi

  if [ -f /etc/netconfig ]; then
    echo "** Disabling IPv6 in netconfig..."
    cp -p /etc/netconfig /etc/netconfig.${DATE}
    sed -e '/inet6/d' -i /etc/netconfig
  fi

  echo "** Disabling IPv6 in /etc/sysconfig/network..."
  # https://github.com/fcaviggia/hardening-script-el6/blob/master/toggle_ipv6.sh
  `grep -q IPV6INIT /etc/sysconfig/network`
  if [ $? -ne 0 ]; then
    echo "IPV6INIT=no" >> /etc/sysconfig/network
  else
    sed -i "/IPV6INIT/s/yes/no/" /etc/sysconfig/network
  fi
  for NET in $(ls /etc/sysconfig/network-scripts/ifcfg*); do
    echo "** Disabling IPv6 in ${NET}..."
    `grep -q IPV6INIT $NET`
    if [ $? -ne 0 ]; then
      echo "IPV6INIT=no" >> $NET
    else
      sed -i "/IPV6INIT/s/yes/no/" $NET
    fi
  done
  echo "** Unloading IPv6 kernel module..."
  rmmod ipv6 &>/dev/null
  echo "** Stopping IPv6 firewall..."
  service ip6tables stop
  chkconfig ip6tables off

elif [ "$OS" == Debian -o "$OS" == Ubuntu ]; then
  echo "** Disabling IPv6 kernel configuration..."
  if grep -q net.ipv6.conf.all.disable_ipv6 /etc/sysctl.conf; then
    sed -i -e '/^net.ipv6.conf.all.disable_ipv6/d' /etc/sysctl.conf
  fi
  if grep -q net.ipv6.conf.default.disable_ipv6 /etc/sysctl.conf; then
    sed -i -e '/^net.ipv6.conf.default.disable_ipv6/d' /etc/sysctl.conf
  fi
  if grep -q net.ipv6.conf.lo.disable_ipv6 /etc/sysctl.conf; then
    sed -i -e '/^net.ipv6.conf.lo.disable_ipv6/d' /etc/sysctl.conf
  fi
  # https://askubuntu.com/questions/440649/how-to-disable-ipv6-in-ubuntu-14-04
  echo "# Tuning for Hadoop installation." >/etc/sysctl.d/cloudera-ipv6.conf
  echo "# CLAIRVOYANT" >>/etc/sysctl.d/cloudera-ipv6.conf
  echo "net.ipv6.conf.all.disable_ipv6 = 1" >>/etc/sysctl.d/cloudera-ipv6.conf
  echo "net.ipv6.conf.default.disable_ipv6 = 1" >>/etc/sysctl.d/cloudera-ipv6.conf
  echo "net.ipv6.conf.lo.disable_ipv6 = 1" >>/etc/sysctl.d/cloudera-ipv6.conf
  chown root:root /etc/sysctl.d/cloudera-ipv6.conf
  chmod 0644 /etc/sysctl.d/cloudera-ipv6.conf
  service procps start

  echo "** Disabling IPv6 in /etc/ssh/sshd_config..."
  cp -p /etc/ssh/sshd_config /etc/ssh/sshd_config.${DATE}
  sed -e '/# CLAIRVOYANT$/d' \
      -e '/^AddressFamily /d' \
      -e '/^ListenAddress /d' \
      -i /etc/ssh/sshd_config
#mja needs work : assumes 0.0.0.0
  cat <<EOF >>/etc/ssh/sshd_config
# Hadoop: Disable IPv6 support # CLAIRVOYANT
AddressFamily inet             # CLAIRVOYANT
ListenAddress 0.0.0.0          # CLAIRVOYANT
# Hadoop: Disable IPv6 support # CLAIRVOYANT
EOF
  service ssh restart

  if [ -f /etc/netconfig ]; then
    echo "** Disabling IPv6 in netconfig..."
    cp -p /etc/netconfig /etc/netconfig.${DATE}
    sed -e '/inet6/d' -i /etc/netconfig
  fi
fi

