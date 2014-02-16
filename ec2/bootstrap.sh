#!/bin/bash

export DEBIAN_FRONTEND=noninteractive

# enable j-d-g repos
if [ -r /etc/apt/sources.list.d/jenkins-debian-glue.list ] ; then
  echo "/etc/apt/sources.list.d/jenkins-debian-glue.list exists already"
else
  echo "deb     http://jenkins.grml.org/debian jenkins-debian-glue main" | sudo tee -a /etc/apt/sources.list.d/jenkins-debian-glue.list
fi
wget -O - http://jenkins.grml.org/debian/C525F56752D4A654.asc | sudo apt-key add -

if [ -r /usr/share/keyrings/ubuntu-archive-keyring.gpg ] ; then
  echo "/usr/share/keyrings/ubuntu-archive-keyring.gpg exists already"
else
  wget -O ubuntu-keyring_2012.05.19_all.deb \
    http://de.archive.ubuntu.com/ubuntu/pool/main/u/ubuntu-keyring/ubuntu-keyring_2012.05.19_all.deb
  dpkg -i ubuntu-keyring_2012.05.19_all.deb
fi

# make sure we use up2date packages
sudo apt-get update
sudo apt-get -y upgrade

# packages required for building on slaves
sudo apt-get -y install jenkins-debian-glue-buildenv jenkins-debian-glue-buildenv-taptools jenkins-debian-glue-buildenv-lintian openjdk-7-jre-headless

# commodity packages
sudo apt-get -y install screen zsh vim

# get rid of installation packages
sudo apt-get clean

if [ -r /etc/jenkins/pbuilderrc ] ; then
  echo "/etc/jenkins/pbuilderrc exists already"
else
  sudo tee -a /etc/jenkins/pbuilderrc >/dev/null <<EOF
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

for distri in jessie lenny lucid precise squeeze wheezy ; do
  arch=amd64
  if [ -d /var/cache/pbuilder/base-${distri}-${arch}.cow ] ; then
    echo "/var/cache/pbuilder/base-${distri}-${arch}.cow exists already"
  else
    sudo cowbuilder --create --basepath /var/cache/pbuilder/base-${distri}-${arch}.cow --distribution ${distri} --debootstrapopts --arch --debootstrapopts ${arch} --debootstrapopts --variant=buildd --configfile=/etc/jenkins/pbuilderrc
  fi

  arch=i386
  if [ -d /var/cache/pbuilder/base-${distri}-${arch}.cow ] ; then
    echo "/var/cache/pbuilder/base-${distri}-${arch}.cow exists already"
  else
    sudo cowbuilder --create --basepath /var/cache/pbuilder/base-${distri}-${arch}.cow --distribution ${distri} --debootstrapopts --arch --debootstrapopts ${arch} --debootstrapopts --variant=buildd --configfile=/etc/jenkins/pbuilderrc
  fi
done
