#!/bin/bash

set -e

# depending on the Debian version we're running on adjust runtime behavior
DEBIAN_VERSION="$(lsb_release -c -s)"

usage() { # Function: Print a help message.
  echo "$0 creates (or updates) Debian + Ubuntu build environments"
  echo
  echo "Usage: $0 [ -u ] distribution"
  echo
  echo "To list supported distributions run: $0 -l"
  echo
}

list_supported_distributions() {
  for f in \
    bionic \
    bookworm \
    bullseye \
    focal \
    jammy \
    noble \
    trixie \
    trusty \
    xenial
  do
    echo "$f"
  done
}

exit_abnormal() { # Function: Exit with error.
  usage >&2
  exit 1
}

UPDATE=false
while getopts "hlu" options; do
  case "${options}" in
    h) usage; exit 0;;
    l) list_supported_distributions ; exit 0 ;;
    u) UPDATE=true;;
    :) echo "Error: -${OPTARG} requires an argument."; exit_abnormal;;
    *) exit_abnormal;;
  esac
done
shift $((OPTIND-1))

if [[ $# != 1 ]] ; then
  echo "Error: bad number of arguments" 1>&2
  echo
  usage >&2
  exit 1
fi
distri=${1}


if [ "$(id -u 2>/dev/null)" != 0 ] ; then
  echo "Error: please execute this script as user root" >&2
  exit 1
fi

echo "Starting at $(date)"

echo "disable unattended-upgrades service"
systemctl stop unattended-upgrades.service
systemctl disable unattended-upgrades.service

export DEBIAN_FRONTEND=noninteractive
export DEBIAN_PRIORITY=critical

install_ubuntu_keyring() {
  wget -O ubuntu-keyring_2021.03.26_all.deb \
    http://de.archive.ubuntu.com/ubuntu/pool/main/u/ubuntu-keyring/ubuntu-keyring_2021.03.26_all.deb
  echo "0d0e7ed6b112f5d03eabf3c7eb01ebdacf9c57714b279e90495cfc58c8c4520f  ubuntu-keyring_2021.03.26_all.deb" > ubuntu-keyring_2021.03.26_all.deb.sha256
  if sha256sum -c ubuntu-keyring_2021.03.26_all.deb.sha256 >/dev/null ; then
    dpkg -i ubuntu-keyring_2021.03.26_all.deb
  else
    echo "Error: wrong checksum for ubuntu-keyring_2021.03.26_all.deb :-/" >&2
    exit 1
  fi
}

if [ -r /usr/share/keyrings/ubuntu-archive-keyring.gpg ] ; then
  echo "!!! /usr/share/keyrings/ubuntu-archive-keyring.gpg exists already !!!"

  if ! gpg /usr/share/keyrings/ubuntu-archive-keyring.gpg | grep -q 871920D1991BC93C ; then
    echo "!!! /usr/share/keyrings/ubuntu-archive-keyring.gpg is outdated - refreshing !!!"
    install_ubuntu_keyring
  fi
else
  install_ubuntu_keyring
fi

if grep -q 'http.debian.net' /etc/apt/sources.list ; then
  echo "!!! Setting deb.debian.org as Debian mirror in /etc/apt/sources.list !!!"
  sed -i "s/http.debian.net/deb.debian.org/" /etc/apt/sources.list
fi

APT_OPTIONS=()

# make sure we don't get stuck if debconf wants to pop up because of a modified conf file
APT_OPTIONS+=(-o Dpkg::Options::=--force-confdef)
APT_OPTIONS+=(-o Dpkg::Options::=--force-confold)

step=5
while [[ $step -ne 0 ]]; do
  echo "$(date) check[$step] /var/lib/dpkg/lock"
  if lsof /var/lib/dpkg/lock >/dev/null 2>&1 ; then
    echo "$(date) dpkg lock in use, go to sleep for a while[${step}]"
    sleep 5
    step=$((step-1))
  else
    echo "$(date) check passed /var/lib/dpkg/lock"
    step=0
  fi
done

if ! apt-get "${APT_OPTIONS[@]}" update ; then
  echo "Retrying apt-get update once more after failure in 5 secs"
  sleep 5
  apt-get "${APT_OPTIONS[@]}" update
fi

apt-get -y "${APT_OPTIONS[@]}" upgrade
apt-get -y "${APT_OPTIONS[@]}" dist-upgrade

# packages required for building on slaves
apt-get -y "${APT_OPTIONS[@]}" install jenkins-debian-glue-buildenv facter eatmydata

case "${DEBIAN_VERSION}" in
  bullseye)
    apt-get -y "${APT_OPTIONS[@]}" install -t bullseye-backports debootstrap
    # required for recent Jenkins versions
    apt-get -y "${APT_OPTIONS[@]}" remove default-jdk-headless openjdk-11-jdk-headless openjdk-11-jre-headless
    apt-get -y "${APT_OPTIONS[@]}" install openjdk-17-jre-headless ca-certificates-java
    ;;
  *)
    apt-get -y "${APT_OPTIONS[@]}" install default-jdk-headless ca-certificates-java
    ;;
esac

# packages required for static checks
apt-get -y "${APT_OPTIONS[@]}" install cppcheck

# for ubuntu 22.04 / zstd support
apt-get -y "${APT_OPTIONS[@]}" install zstd

# commodity packages
apt-get -y "${APT_OPTIONS[@]}" install screen zsh vim

# get rid of installation packages
apt-get clean

echo "!!! Setting up /etc/jenkins/pbuilderrc !!!"
cat > /etc/jenkins/pbuilderrc << "EOF"
# distribution specific configuration
case "$distribution" in
  xenial|bionic|focal|jammy|noble)
    MIRRORSITE="http://archive.ubuntu.com/ubuntu/"
    # we need key id 40976EAF437D05B5
    DEBOOTSTRAPOPTS=("${DEBOOTSTRAPOPTS[@]}" "--keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg")
    # cowdancer is in universe
    COMPONENTS="main universe"
    # security and updates
    OTHERMIRROR="deb http://archive.ubuntu.com/ubuntu/ ${distribution}-updates main universe|deb-src http://security.ubuntu.com/ubuntu ${distribution}-security main universe"
    # package install speedup
    EXTRAPACKAGES="eatmydata"
    export LD_PRELOAD="${LD_PRELOAD:+$LD_PRELOAD:}libeatmydata.so"
    ;;
  trusty)
    # lacks eatmydata package, so explicitly configure it
    MIRRORSITE="http://archive.ubuntu.com/ubuntu/"
    # we need key id 40976EAF437D05B5
    DEBOOTSTRAPOPTS=("${DEBOOTSTRAPOPTS[@]}" "--keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg")
    # cowdancer is in universe
    COMPONENTS="main universe"
    # security and updates
    OTHERMIRROR="deb http://archive.ubuntu.com/ubuntu/ ${distribution}-updates main universe|deb-src http://security.ubuntu.com/ubuntu ${distribution}-security main universe"
    # ensure it's unset
    unset LD_PRELOAD
    ;;
  precise)
    # lacks eatmydata package, so explicitly configure it
    # also EOL nowadays, so need other mirror
    MIRRORSITE="http://old-releases.ubuntu.com/ubuntu/"
    # we need key id 40976EAF437D05B5
    DEBOOTSTRAPOPTS=("${DEBOOTSTRAPOPTS[@]}" "--keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg")
    # cowdancer is in universe
    COMPONENTS="main universe"
    # security and updates
    OTHERMIRROR="deb http://old-releases.ubuntu.com/ubuntu/ ${distribution}-updates main universe|deb-src http://old-releases.ubuntu.com/ubuntu ${distribution}-security main universe"
    # ensure it's unset
    unset LD_PRELOAD
    ;;
  bullseye|bookworm|trixie)
    MIRRORSITE="http://deb.debian.org/debian"
    # security and updates
    OTHERMIRROR="deb http://security.debian.org/debian-security ${distribution}-security main"
    # package install speedup
    EXTRAPACKAGES="eatmydata"
    export LD_PRELOAD="${LD_PRELOAD:+$LD_PRELOAD:}libeatmydata.so"
    ;;
  *)
    MIRRORSITE="http://deb.debian.org/debian"
    # package install speedup
    EXTRAPACKAGES="eatmydata"
    export LD_PRELOAD="${LD_PRELOAD:+$LD_PRELOAD:}libeatmydata.so"
    ;;
esac

case "$architecture" in
  arm64)
    MIRRORSITE=$(echo "${MIRRORSITE}" | sed 's#archive.ubuntu.com/ubuntu#ports.ubuntu.com#')
    OTHERMIRROR=$(echo "${OTHERMIRROR}" | sed 's#archive.ubuntu.com/ubuntu#ports.ubuntu.com#')
    OTHERMIRROR=$(echo "${OTHERMIRROR}" | sed 's#security.ubuntu.com/ubuntu#ports.ubuntu.com#')
  ;;
esac
EOF

echo "!!! Setting up /etc/sudoers.d/pbuilder !!!"
cat > /etc/sudoers.d/pbuilder <<EOF
Defaults  env_keep+="architecture branch distribution release ARCH DEB_* DIST JOB_NAME MIRROR PIUPARTS_* LINTIAN*"
EOF

if grep -q '^PBUILDER_CONFIG=' /etc/jenkins/debian_glue 2>/dev/null ; then
  echo "!!! /etc/jenkins/debian_glue with PBUILDER_CONFIG exists already !!!"
else
  echo "PBUILDER_CONFIG=/etc/jenkins/pbuilderrc" >> /etc/jenkins/debian_glue
fi

if ! [ -e /usr/share/debootstrap/scripts/noble ] ; then
  echo "Debootstrap version doesn't know about Ubuntu noble yet, creating according symlink"
  ln -s gutsy /usr/share/debootstrap/scripts/noble
fi

if ! [ -e /usr/share/debootstrap/scripts/jammy ] ; then
  echo "Debootstrap version doesn't know about Ubuntu jammy yet, creating according symlink"
  ln -s gutsy /usr/share/debootstrap/scripts/jammy
fi

if ! [ -e /usr/share/debootstrap/scripts/focal ] ; then
  echo "Debootstrap version doesn't know about Ubuntu focal yet, creating according symlink"
  ln -s gutsy /usr/share/debootstrap/scripts/focal
fi

if ! [ -e /usr/share/debootstrap/scripts/bionic ] ; then
  echo "Debootstrap version doesn't know about Ubuntu bionic yet, creating according symlink"
  ln -s gutsy /usr/share/debootstrap/scripts/bionic
fi

if ! [ -e /usr/share/debootstrap/scripts/xenial ] ; then
  echo "Debootstrap version doesn't know about Ubuntu xenial yet, creating according symlink"
  ln -s gutsy /usr/share/debootstrap/scripts/xenial
fi

if ! [ -e /usr/share/debootstrap/scripts/bullseye ] ; then
  echo "Debootstrap version doesn't know about Debian bullseye yet, creating according symlink"
  ln -s sid /usr/share/debootstrap/scripts/bullseye
fi

if ! [ -e /usr/share/debootstrap/scripts/bookworm ] ; then
  echo "Debootstrap version doesn't know about Debian bookworm yet, creating according symlink"
  ln -s sid /usr/share/debootstrap/scripts/sid
fi

if ! [ -e /usr/share/debootstrap/scripts/trixie ] ; then
  echo "Debootstrap version doesn't know about Debian trixie yet, creating according symlink"
  ln -s sid /usr/share/debootstrap/scripts/sid
fi

export distribution=${distri} # for usage in pbuilderrc

prepare_cowbuilder() {
  if ! [ -d "/var/cache/pbuilder/base-${distri}-${arch}.cow" ] ; then
    (
      # shellcheck disable=SC2030
      export architecture=${arch} # for usage in pbuilderrc
      # shellcheck disable=SC1091
      source /etc/jenkins/pbuilderrc
      eatmydata cowbuilder --create \
        --basepath "/var/cache/pbuilder/base-${distri}-${arch}.cow" \
        --distribution "${distri}" --debootstrapopts --arch \
        --debootstrapopts "${arch}" --debootstrapopts --variant=buildd \
        --configfile=/etc/jenkins/pbuilderrc \
        --mirror "${MIRRORSITE}" \
        --othermirror="${OTHERMIRROR}"
    )
  else
    if $UPDATE ; then
      echo "!!! Executing update for cowbuilder as requested !!!"
      (
        # shellcheck disable=SC2031
        export architecture=${arch} # for usage in pbuilderrc
        # shellcheck disable=SC1091
        source /etc/jenkins/pbuilderrc
        eatmydata cowbuilder --update \
          --basepath "/var/cache/pbuilder/base-${distri}-${arch}.cow" \
          --distribution "${distri}" \
          --configfile=/etc/jenkins/pbuilderrc \
          --mirror "${MIRRORSITE}" \
          --othermirror="${OTHERMIRROR}" --override-config
      )
    else
      echo "!!! /var/cache/pbuilder/base-${distri}-${arch}.cow exists already (execute '$0 --update' to refresh it) !!!"
    fi
  fi

  if $UPDATE ; then
    echo "!!! (Re)creating tarballs for piuparts usage as requested !!!"
    echo "Creating /var/cache/pbuilder/base-${distri}-${arch}.tgz for piuparts usage"
    pushd "/var/cache/pbuilder/base-${distri}-${arch}.cow" >/dev/null
    tar acf "/var/cache/pbuilder/base-${distri}-${arch}.tgz" ./*
    popd >/dev/null
  else
    if [ -r "/var/cache/pbuilder/base-${distri}-${arch}.tgz" ] ; then
      echo "!!! /var/cache/pbuilder/base-${distri}-${arch}.tgz exists already (execute '$0 --update' to force (re)building) !!!"
    else
      echo "Creating /var/cache/pbuilder/base-${distri}-${arch}.tgz for piuparts usage"
      pushd "/var/cache/pbuilder/base-${distri}-${arch}.cow" >/dev/null
      tar acf "/var/cache/pbuilder/base-${distri}-${arch}.tgz" ./*
      popd >/dev/null
    fi
  fi
}

for arch in amd64 arm64 ; do
  prepare_cowbuilder
done

echo "Cleaning pbuilder's apt cache"
rm -f /var/cache/pbuilder/aptcache/*

echo "Finished at $(date)"
