#!/bin/bash

if [ "$(id -u 2>/dev/null)" != 0 ] ; then
  echo "Error: please execute this script as user root" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

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
    http://de.archive.ubuntu.com/ubuntu/pool/main/u/ubuntu-keyring/ubuntu-keyring_2012.05.19_all.deb
  dpkg -i ubuntu-keyring_2012.05.19_all.deb
fi

# make sure we use up2date packages
apt-get update
apt-get -y upgrade

# packages required for building on slaves
apt-get -y install jenkins-debian-glue-buildenv jenkins-debian-glue-buildenv-taptools jenkins-debian-glue-buildenv-lintian jenkins-debian-glue-buildenv-piuparts openjdk-7-jre-headless ntp facter

# commodity packages
apt-get -y install screen zsh vim

# get rid of installation packages
apt-get clean

if [ -r /etc/jenkins/pbuilderrc ] ; then
  echo "!!! /etc/jenkins/pbuilderrc exists already !!!"
else
  cat > /etc/jenkins/pbuilderrc <<EOF
# ccache
CCACHEDIR=/var/cache/pbuilder/ccache

# ubuntu specific configuration
case "$distribution" in
  precise|lucid)
    MIRRORSITE="http://ie.archive.ubuntu.com/ubuntu/"
    # we need key id 40976EAF437D05B5
    DEBOOTSTRAPOPTS=("${DEBOOTSTRAPOPTS[@]}" "--keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg")
    # cowdancer is in universe
    COMPONENTS="main universe"
    ;;
  lenny)
    MIRRORSITE="http://archive.debian.org/debian/"
    ;;
  *)
    MIRRORSITE="http://http.debian.net/debian"
    ;;
esac
EOF
fi

echo "!!! Setting up /etc/sudoers.d/pbuilder !!!"
cat > /etc/sudoers.d/pbuilder <<EOF
Defaults  env_keep+="DEB_* release branch distribution JOB_NAME MIRROR"
EOF

if grep -q '^PBUILDER_CONFIG=' /etc/jenkins/debian_glue 2>/dev/null ; then
  echo "!!! /etc/jenkins/debian_glue with PBUILDER_CONFIG exists already !!!"
else
  echo "PBUILDER_CONFIG=/etc/jenkins/pbuilderrc" >> /etc/jenkins/debian_glue
fi

for distri in jessie lenny lucid precise squeeze wheezy ; do
  export distribution=$distri # for usage in pbuilderrc

  arch=amd64
  if [ -d /var/cache/pbuilder/base-${distri}-${arch}.cow ] ; then
    echo "!!! /var/cache/pbuilder/base-${distri}-${arch}.cow exists already !!!"
  else
    cowbuilder --create --basepath /var/cache/pbuilder/base-${distri}-${arch}.cow --distribution ${distri} --debootstrapopts --arch --debootstrapopts ${arch} --debootstrapopts --variant=buildd --configfile=/etc/jenkins/pbuilderrc
  fi

  arch=i386
  if [ -d /var/cache/pbuilder/base-${distri}-${arch}.cow ] ; then
    echo "!!! /var/cache/pbuilder/base-${distri}-${arch}.cow exists already !!!"
  else
    cowbuilder --create --basepath /var/cache/pbuilder/base-${distri}-${arch}.cow --distribution ${distri} --debootstrapopts --arch --debootstrapopts ${arch} --debootstrapopts --variant=buildd --configfile=/etc/jenkins/pbuilderrc
  fi
done
