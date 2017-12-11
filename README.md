README for kamailio-deb-jenkins
===============================

This repository provides configuration and scripts as used by the server
for building Debian packages for the [Kamailio project](http://www.kamailio.org/).

Development of this setup is sponsored by [Sipwise](http://www.sipwise.com/).


Involved Software
-----------------

* [Debian](http://www.debian.org/) (version 8.X, amd64)
* [Jenkins](http://jenkins-ci.org/)
* [jenkins-debian-glue](http://jenkins-debian-glue.org/)
* [Jenkins Job Builder](http://ci.openstack.org/jenkins-job-builder/)


Deployment instructions
-----------------------

NOTE: Using user admin for administration as present on EC2, adjust if necessary.

Install etckeeper for tracking changes in /etc:

    sudo apt-get -y install etckeeper git

Automatically deploy [jenkins-debian-glue](http://jenkins-debian-glue.org/):

    wget --no-check-certificate https://raw.github.com/mika/jenkins-debian-glue/master/puppet/apply.sh
    sudo bash ./apply.sh $PASSWORD

Support providing additional configuration to cowbuilder + related tools:

    sudo tee -a /etc/sudoers.d/jenkins >/dev/null <<EOF
    # for cowbuilder/pbuilder/... instructions in kamailio-deb-jenkins setup:
    Defaults  env_keep+="release branch distribution JOB_NAME MIRROR DEB_BUILD_OPTIONS"
    EOF

Grab a copy of this repository:

    git clone https://github.com/sipwise/kamailio-deb-jenkins.git /home/admin/kamailio-deb-jenkins

Adopt pbuilder for usage with building for Ubuntu:

    echo PBUILDER_CONFIG=/etc/jenkins/pbuilderrc | sudo tee -a /etc/jenkins/debian_glue
    sudo cp /home/admin/kamailio-deb-jenkins/pbuilder/pbuilderrc /etc/jenkins/pbuilderrc
    sudo dpkg -i /home/admin/kamailio-deb-jenkins/debs/ubuntu-keyring_2012.05.19_all.deb

Deploy nginx as proxy for Jenkins:

    sudo apt-get -y install nginx
    sudo openssl req -days 3650 -nodes -new -x509 -keyout /etc/ssl/private/server.key -out /etc/ssl/private/server.cert
    sudo cp /home/admin/kamailio-deb-jenkins/nginx/default /etc/nginx/sites-available/default
    sudo /etc/init.d/nginx restart

Set up Debian repository directories:

    sudo mkdir /srv/repository
    sudo chown jenkins /srv/repository
    sudo ln -s /srv/repository/ /srv/debian

GPG key setup for Debian repository:

    sudo apt-get install haveged
    sudo -s
    su - jenkins
    gpg --gen-key # note $KEY_ID
    gpg --armor --export $KEY_ID --output /srv/debian/kamailiodebkey.gpg
    echo KEY_ID=$KEY_ID | sudo tee -a /etc/jenkins/debian_glue

Set up jenkins-job-builder:

    sudo tee -a /etc/jenkins_jobs/jenkins_jobs2.ini >/dev/null <<EOF
    [jenkins]
    user=jenkins-job-builder
    password=$PASSWORD
    url=http://localhost:8080/
    EOF

Install Matrix Reloaded Jenkins Plugin:

    sudo wget --no-check-certificate -O /var/lib/jenkins/plugins/matrix-reloaded.hpi http://updates.jenkins-ci.org/latest/matrix-reloaded.hpi
    sudo chown jenkins:nogroup /var/lib/jenkins/plugins/matrix-reloaded.hpi

Install Build Blocker Jenkins Plugin:

    sudo wget --no-check-certificate -O /var/lib/jenkins/plugins/build-blocker-plugin.hpi http://updates.jenkins-ci.org/latest/build-blocker-plugin.hpi
    sudo chown jenkins:nogroup /var/lib/jenkins/plugins/build-blocker-plugin.hpi

Install CppCheck Jenkins Plugin:

    sudo wget --no-check-certificate -O /var/lib/jenkins/plugins/cppcheck.hpi http://updates.jenkins-ci.org/latest/cppcheck.hpi
    sudo chown jenkins:nogroup /var/lib/jenkins/plugins/cppcheck.hpi

Install Build-timeout Plugin:

    sudo wget --no-check-certificate -O /var/lib/jenkins/plugins/build-timeout.hpi http://updates.jenkins-ci.org/latest/build-timeout.hpi
    sudo chown jenkins:nogroup /var/lib/jenkins/plugins/build-timeout.hpi

Adjust for usage with headless Java (if not already present):

    echo JAVA_ARGS="-Djava.awt.headless=true" | sudo tee -a /etc/default/jenkins

Fix headless issue with Java (if still running openjdk version 6, doesn't seem to be relevant for openjdk >=7):

    sudo apt-get install ttf-dejavu
    sudo java -jar /usr/lib/jvm/java-6-openjdk-common/jre/lib/compilefontconfig.jar \
      /etc/java-6-openjdk/fontconfig.properties \
      /usr/lib/jvm/java-6-openjdk-common/jre/lib/fontconfig.bfc
    sudo /etc/init.d/jenkins restart

Generate according Jenkins jobs:

    cd /home/admin/kamailio-deb-jenkins/jjb
    make

Build slave setup
-----------------

It's possible to run the build process on a separate Jenkins slave.
To set up the build slave follow those steps:

    sudo apt-get -y install git
    git clone https://github.com/sipwise/kamailio-deb-jenkins
    cd kamailio-deb-jenkins/
    sudo ./ec2/bootstrap.sh

Depending on your setup, connect the slave to your master then (SSH, swarm plugin, Amazon EC2 plugin,...).

Questions?
----------

For Jenkins/Build environment related questions contact [Michael Prokop](https://github.com/mika/) (mprokop (at) sipwise dot com),
for Kamailio (packaging) related questions contact [Victor Seva](https://github.com/linuxmaniac/) (linuxmaniac (at) torreviejawireless dot org).
