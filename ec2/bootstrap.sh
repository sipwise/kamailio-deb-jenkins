#!/bin/bash
SRC_DIR=$(dirname "$(realpath "$0")")
set -e

# config
DEBIAN_MIRROR="ftp.de.debian.org"

if [ "$1" == "-h" ] || [ "$1" == "--help" ] ; then
  echo "$0 creates (or updates) Debian + Ubuntu build environments"
  echo
  echo "Usage: $0 [--update]"
  exit 0
fi

if [ "$(id -u 2>/dev/null)" != 0 ] ; then
  echo "Error: please execute this script as user root" >&2
  exit 1
fi

UPDATE=false
if [ "$1" == "--update" ] ; then
  UPDATE=true
fi

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

if [ -r /usr/share/keyrings/ubuntu-archive-keyring.gpg ] ; then
  echo "!!! /usr/share/keyrings/ubuntu-archive-keyring.gpg exists already !!!"
else
  wget -O ubuntu-keyring_2012.05.19_all.deb \
    http://archive.ubuntu.com/ubuntu/pool/main/u/ubuntu-keyring/ubuntu-keyring_2012.05.19_all.deb
  dpkg -i ubuntu-keyring_2012.05.19_all.deb
fi

# make sure we use up2date packages
echo "!!! Enabling Debian backports !!!"
cat > /etc/apt/sources.list.d/backports.list << EOF
deb http://${DEBIAN_MIRROR}/debian jessie-backports main
EOF

if grep -q 'http.debian.net' /etc/apt/sources.list ; then
  echo "!!! Setting ${DEBIAN_MIRROR} as Debian mirror in /etc/apt/sources.list !!!"
  sed -i "s/http.debian.net/${DEBIAN_MIRROR}/" /etc/apt/sources.list
fi

# make sure we don't get stuck if debconf wants to pop up because of a modified conf file
APT_OPTIONS='-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold'

if ! apt-get update ; then
  echo "Retrying apt-get update once more after failure"
  apt-get update
fi

apt-get -y $APT_OPTIONS upgrade
apt-get -y $APT_OPTIONS dist-upgrade

# packages required for building on slaves
apt-get -y $APT_OPTIONS install jenkins-debian-glue-buildenv ntp facter eatmydata

# packages required from jessie-backports
apt-get -y $APT_OPTIONS install -t jessie-backports ca-certificates-java openjdk-8-jre-headless
apt-get -y $APT_OPTIONS remove openjdk-7-jre-headless default-jre-headless

# packages required for static checks
apt-get -y $APT_OPTIONS install cppcheck

# make sure we use an up2date piuparts version, e.g.
# to solve https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=699028
# and lintian to solve control.tar.xz error (needs >= 2.5.50)
apt-get -y $APT_OPTIONS install -t jessie-backports piuparts lintian

# commodity packages
apt-get -y $APT_OPTIONS install screen zsh vim

# get rid of installation packages
apt-get clean

echo "!!! Setting up /etc/jenkins/pbuilderrc !!!"
cat > /etc/jenkins/pbuilderrc <<EOF
# distribution specific configuration
case "\$distribution" in
  xenial)
    MIRRORSITE="http://archive.ubuntu.com/ubuntu/"
    # we need key id 40976EAF437D05B5
    DEBOOTSTRAPOPTS=("\${DEBOOTSTRAPOPTS[@]}" "--keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg")
    # cowdancer is in universe
    COMPONENTS="main universe"
    # package install speedup
    EXTRAPACKAGES="eatmydata"
    export LD_PRELOAD="\${LD_PRELOAD:+\$LD_PRELOAD:}libeatmydata.so"
    ;;
  trusty|precise)
    # lacks eatmydata package, so explicitely configure it
    MIRRORSITE="http://archive.ubuntu.com/ubuntu/"
    # we need key id 40976EAF437D05B5
    DEBOOTSTRAPOPTS=("\${DEBOOTSTRAPOPTS[@]}" "--keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg")
    # cowdancer is in universe
    COMPONENTS="main universe"
    # ensure it's unset
    unset LD_PRELOAD
    ;;
  squeeze)
    # lacks eatmydata package, so explicitely configure it
    # nowadays also resides on archive
    MIRRORSITE="http://archive.debian.org/debian/"
    # ensure it's unset
    unset LD_PRELOAD
    ;;
  wheezy|jessie|stretch|buster|*)
    MIRRORSITE="http://${DEBIAN_MIRROR}/debian"
    # package install speedup
    EXTRAPACKAGES="eatmydata"
    export LD_PRELOAD="\${LD_PRELOAD:+\$LD_PRELOAD:}libeatmydata.so"
    ;;
esac
EOF

echo "!!! Setting up /etc/sudoers.d/pbuilder !!!"
cat > /etc/sudoers.d/pbuilder <<EOF
Defaults  env_keep+="DEB_* PIUPARTS_* release branch distribution architecture JOB_NAME MIRROR DIST ARCH"
EOF

if grep -q '^PBUILDER_CONFIG=' /etc/jenkins/debian_glue 2>/dev/null ; then
  echo "!!! /etc/jenkins/debian_glue with PBUILDER_CONFIG exists already !!!"
else
  echo "PBUILDER_CONFIG=/etc/jenkins/pbuilderrc" >> /etc/jenkins/debian_glue
fi

if ! grep -q 'PIUPARTS_COMPONENTS' /usr/bin/piuparts_wrapper ; then
  echo "!!! patching /usr/bin/piuparts_wrapper !!!"
  (
    cd /usr/bin/
    patch -p2 < ${SRC_DIR}/patches/piuparts_wrapper-don-t-use-COMPONENTS-environment-va.patch
  )
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

for distri in buster stretch jessie wheezy squeeze xenial trusty precise ; do
  export distribution=$distri # for usage in pbuilderrc

  for arch in amd64 i386 ; do
    if ! [ -d /var/cache/pbuilder/base-${distri}-${arch}.cow ] ; then
      eatmydata cowbuilder --create --basepath /var/cache/pbuilder/base-${distri}-${arch}.cow --distribution ${distri} --debootstrapopts --arch --debootstrapopts ${arch} --debootstrapopts --variant=buildd --configfile=/etc/jenkins/pbuilderrc
    else
      if $UPDATE ; then
        # replace http.debian.net with our actual Debian mirror
        if grep -q 'http.debian.net' /var/cache/pbuilder/base-${distri}-${arch}.cow/etc/apt/sources.list ; then
          echo "!!! Setting $DEBIAN_MIRROR as Debian mirror in /var/cache/pbuilder/base-${distri}-${arch}.cow/etc/apt/sources.list !!!"
          sed -i "s/http.debian.net/${DEBIAN_MIRROR}/" /var/cache/pbuilder/base-${distri}-${arch}.cow/etc/apt/sources.list
        fi

        echo "!!! Executing update for cowbuilder as requested !!!"
        eatmydata cowbuilder --update --basepath /var/cache/pbuilder/base-${distri}-${arch}.cow --distribution ${distri} --configfile=/etc/jenkins/pbuilderrc
      else
        echo "!!! /var/cache/pbuilder/base-${distri}-${arch}.cow exists already !!!"
      fi
    fi

    echo "Creating /var/cache/pbuilder/base-${distri}-${arch}.tgz for piuparts usage"
    pushd "/var/cache/pbuilder/base-${distri}-${arch}.cow" >/dev/null
    tar acf /var/cache/pbuilder/base-${distri}-${arch}.tgz *
    popd >/dev/null
  done
done

echo "Cleaning pbuilder's apt cache"
rm -f /var/cache/pbuilder/aptcache/*
