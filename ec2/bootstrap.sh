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
    buster \
    focal \
    jammy \
    jessie \
    stretch \
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

# enable j-d-g repos
if [ -r /etc/apt/sources.list.d/jenkins-debian-glue.list ] ; then
  echo "!!! /etc/apt/sources.list.d/jenkins-debian-glue.list exists already !!!"
else
  echo "deb     http://jenkins.grml.org/debian jenkins-debian-glue main" > /etc/apt/sources.list.d/jenkins-debian-glue.list
fi

if apt-key list | grep -q 52D4A654 ; then
  echo "!!! GnuPG key 52D4A654 already listed in apt-key setup !!!"
else
  wget -O - http://jenkins.grml.org/debian/C525F56752D4A654.asc | apt-key add -
fi

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

  if gpg /usr/share/keyrings/ubuntu-archive-keyring.gpg | grep -q 871920D1991BC93C ; then
    echo "!!! /usr/share/keyrings/ubuntu-archive-keyring.gpg is outdated - refreshing !!!"
    install_ubuntu_keyring
  fi
else
  install_ubuntu_keyring
fi

# jessie repos expired, so disable the repository check iff running on jessie
case "${DEBIAN_VERSION}" in
  jessie)
    echo "!!! Enabling Debian backports for usage on jessie !!!"
    cat > /etc/apt/sources.list.d/backports.list << EOF
deb http://archive.debian.org/debian jessie-backports main
EOF
    ;;
  *)
    echo "!!! Enabling Debian backports !!!"
    cat > /etc/apt/sources.list.d/backports.list << EOF
deb http://deb.debian.org/debian ${DEBIAN_VERSION}-backports main
EOF
  ;;
esac

if grep -q 'http.debian.net' /etc/apt/sources.list ; then
  echo "!!! Setting deb.debian.org as Debian mirror in /etc/apt/sources.list !!!"
  sed -i "s/http.debian.net/deb.debian.org/" /etc/apt/sources.list
fi

# backwards compatibility if running on jessie based slaves
if grep -q 'jessie-updates' /etc/apt/sources.list ; then
  echo "!!! Disabling no-longer-existing jessie-updates in /etc/apt/sources.list !!!"
  sed -i 's/\(^deb.* jessie-updates .*\)/# disabled by ec2\/bootstrap.sh\n# \1/' /etc/apt/sources.list
fi

# make sure we don't get stuck if debconf wants to pop up because of a modified conf file
APT_OPTIONS='-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold'

# jessie repos expired, so disable the repository check iff running on jessie
case "${DEBIAN_VERSION}" in
  jessie)
    APT_OPTIONS="$APT_OPTIONS -o Acquire::Check-Valid-Until=false"
    ;;
esac

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

if ! apt-get $APT_OPTIONS update ; then
  echo "Retrying apt-get update once more after failure in 5 secs"
  sleep 5
  apt-get $APT_OPTIONS update
fi

apt-get -y $APT_OPTIONS upgrade
apt-get -y $APT_OPTIONS dist-upgrade

# packages required for building on slaves
apt-get -y $APT_OPTIONS install jenkins-debian-glue-buildenv facter eatmydata

case "${DEBIAN_VERSION}" in
  jessie)
    apt-get -y $APT_OPTIONS install -t jessie-backports ca-certificates-java openjdk-8-jre-headless
    apt-get -y $APT_OPTIONS remove openjdk-7-jre-headless default-jre-headless
    # required for build-profile support in e.g. rtpengine
    apt-get -y $APT_OPTIONS install -t jessie-backports pbuilder
    # make sure we use an up2date piuparts version, e.g.
    # to solve https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=699028
    # and lintian to solve control.tar.xz error (needs >= 2.5.50)
    apt-get -y $APT_OPTIONS install -t jessie-backports piuparts lintian
    ;;
  stretch)
    apt-get -y $APT_OPTIONS install default-jdk-headless ca-certificates-java
    apt-get -y $APT_OPTIONS install -t stretch-backports pbuilder debootstrap piuparts lintian
    ;;
  bullseye)
    # for ubuntu 22.04 / zstd support
    apt-get -y $APT_OPTIONS install zstd
    apt-get -y $APT_OPTIONS install -t bullseye-backports debootstrap
    ;;
  *)
    apt-get -y $APT_OPTIONS install default-jdk-headless ca-certificates-java
    apt-get -y $APT_OPTIONS install pbuilder piuparts lintian
    ;;
esac

# packages required for static checks
apt-get -y $APT_OPTIONS install cppcheck

# commodity packages
apt-get -y $APT_OPTIONS install screen zsh vim

# get rid of installation packages
apt-get clean

echo "!!! Setting up /etc/jenkins/pbuilderrc !!!"
cat > /etc/jenkins/pbuilderrc << "EOF"
# distribution specific configuration
case "$distribution" in
  xenial|bionic|focal|jammy)
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
  wheezy)
    # nowadays resides on archive
    MIRRORSITE="http://archive.debian.org/debian/"
    # we need key id 6FB2A1C265FFB764
    DEBOOTSTRAPOPTS=("${DEBOOTSTRAPOPTS[@]}" "--keyring=/usr/share/keyrings/debian-archive-removed-keys.gpg")
    # package install speedup
    EXTRAPACKAGES="eatmydata"
    export LD_PRELOAD="${LD_PRELOAD:+$LD_PRELOAD:}libeatmydata.so"
    ;;
  jessie)
    MIRRORSITE="http://deb.debian.org/debian"
    # security and updates
    OTHERMIRROR="deb http://security.debian.org/debian-security ${distribution}/updates main"
    # we need key id CBF8D6FD518E17E1
    DEBOOTSTRAPOPTS=("${DEBOOTSTRAPOPTS[@]}" "--keyring=/usr/share/keyrings/debian-archive-removed-keys.gpg")
    # package install speedup
    EXTRAPACKAGES="eatmydata"
    export LD_PRELOAD="${LD_PRELOAD:+$LD_PRELOAD:}libeatmydata.so"
    ;;
  stretch|buster)
    MIRRORSITE="http://deb.debian.org/debian"
    # security and updates
    OTHERMIRROR="deb http://security.debian.org/debian-security ${distribution}/updates main"
    # package install speedup
    EXTRAPACKAGES="eatmydata"
    export LD_PRELOAD="${LD_PRELOAD:+$LD_PRELOAD:}libeatmydata.so"
    ;;
  bullseye|bookworm)
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

if ! [ -e /usr/share/debootstrap/scripts/stretch ] ; then
  echo "Debootstrap version doesn't know about Debian stretch yet, creating according symlink"
  ln -s sid /usr/share/debootstrap/scripts/stretch
fi

if ! [ -e /usr/share/debootstrap/scripts/buster ] ; then
  echo "Debootstrap version doesn't know about Debian buster yet, creating according symlink"
  ln -s sid /usr/share/debootstrap/scripts/buster
fi

if ! [ -e /usr/share/debootstrap/scripts/bullseye ] ; then
  echo "Debootstrap version doesn't know about Debian bullseye yet, creating according symlink"
  ln -s sid /usr/share/debootstrap/scripts/bullseye
fi

if ! [ -e /usr/share/debootstrap/scripts/bookworm ] ; then
  echo "Debootstrap version doesn't know about Debian bookworm yet, creating according symlink"
  ln -s sid /usr/share/debootstrap/scripts/sid
fi

export distribution=${distri} # for usage in pbuilderrc

for arch in amd64 i386 ; do
  case "${distri}" in
    focal|jammy)
      if [ "${arch}" = "i386" ] ; then
        echo "*** WARN: Ubuntu dropped support for i386 as of 19.10, skipping for ${distri} therefore. ***"
        continue
      fi
      ;;
  esac

  if ! [ -d /var/cache/pbuilder/base-${distri}-${arch}.cow ] ; then
    (
      source /etc/jenkins/pbuilderrc
      eatmydata cowbuilder --create \
        --basepath /var/cache/pbuilder/base-${distri}-${arch}.cow \
        --distribution ${distri} --debootstrapopts --arch \
        --debootstrapopts ${arch} --debootstrapopts --variant=buildd \
        --configfile=/etc/jenkins/pbuilderrc \
        --mirror ${MIRRORSITE} \
        --othermirror="${OTHERMIRROR}"
    )
  else
    if $UPDATE ; then
      echo "!!! Executing update for cowbuilder as requested !!!"
      (
        source /etc/jenkins/pbuilderrc
        eatmydata cowbuilder --update \
          --basepath /var/cache/pbuilder/base-${distri}-${arch}.cow \
          --distribution ${distri} \
          --configfile=/etc/jenkins/pbuilderrc \
          --mirror ${MIRRORSITE} \
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
    tar acf /var/cache/pbuilder/base-${distri}-${arch}.tgz *
    popd >/dev/null
  else
    if [ -r "/var/cache/pbuilder/base-${distri}-${arch}.tgz" ] ; then
      echo "!!! /var/cache/pbuilder/base-${distri}-${arch}.tgz exists already (execute '$0 --update' to force (re)building) !!!"
    else
      echo "Creating /var/cache/pbuilder/base-${distri}-${arch}.tgz for piuparts usage"
      pushd "/var/cache/pbuilder/base-${distri}-${arch}.cow" >/dev/null
      tar acf /var/cache/pbuilder/base-${distri}-${arch}.tgz *
      popd >/dev/null
    fi
  fi

done

echo "Cleaning pbuilder's apt cache"
rm -f /var/cache/pbuilder/aptcache/*

echo "Finished at $(date)"
