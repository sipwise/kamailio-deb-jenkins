README for kamailio-deb-jenkins
===============================

This repository provides configuration and scripts as used by the server
for building Debian packages for the [Kamailio project](http://www.kamailio.org/).

Development of this setup is sponsored by [Sipwise](http://www.sipwise.com/).


Involved Software
-----------------

* [Debian](https://www.debian.org/) (version 9/stretch, amd64)
* [Jenkins](https://jenkins.io/)
* [jenkins-debian-glue](https://jenkins-debian-glue.org/)
* [Jenkins Job Builder](https://docs.openstack.org/infra/jenkins-job-builder/)


Deployment instructions
-----------------------

NOTE: Using user admin for administration as present on EC2, adjust if necessary.

Install etckeeper for tracking changes in /etc:

    sudo apt-get -y install etckeeper git

Automatically deploy [jenkins-debian-glue](http://jenkins-debian-glue.org/):

    wget https://raw.github.com/mika/jenkins-debian-glue/master/puppet/apply.sh
    sudo bash ./apply.sh $PASSWORD

Use custom systemd unit for jenkins service:

    sudo systemctl stop jenkins
    sudo ln -s /home/admin/kamailio-deb-jenkins/jenkins/jenkins.service /etc/systemd/system/jenkins.service
    sudo systemctl daemon-reload
    sudo systemctl restart jenkins

Support providing additional configuration to cowbuilder + related tools:

    sudo tee -a /etc/sudoers.d/jenkins >/dev/null <<EOF
    # for *-binaries job
    jenkins ALL=NOPASSWD: /usr/sbin/cowbuilder, /usr/sbin/chroot
    # for *-piuparts job
    jenkins ALL=NOPASSWD: /usr/sbin/piuparts, /usr/sbin/debootstrap, /usr/bin/piuparts_wrapper

    # for cowbuilder instruction:
    Defaults  env_keep+="architecture branch distribution release ARCH DEB_* DIST JOB_NAME MIRROR PIUPARTS_*"
    EOF

Grab a copy of this repository:

    git clone https://github.com/sipwise/kamailio-deb-jenkins.git /home/admin/kamailio-deb-jenkins

Adopt pbuilder for usage with building for Ubuntu:

    echo PBUILDER_CONFIG=/etc/jenkins/pbuilderrc | sudo tee -a /etc/jenkins/debian_glue
    sudo cp /home/admin/kamailio-deb-jenkins/pbuilder/pbuilderrc /etc/jenkins/pbuilderrc
    sudo dpkg -i /home/admin/kamailio-deb-jenkins/debs/ubuntu-keyring_2012.05.19_all.deb

Deploy nginx as proxy for Jenkins (consider adjusting this using Let's Encrypt SSL certificates though!):

    sudo apt-get -y install nginx
    sudo openssl req -days 3650 -nodes -new -x509 -keyout /etc/ssl/private/server.key -out /etc/ssl/private/server.cert
    sudo cp /home/admin/kamailio-deb-jenkins/nginx/default /etc/nginx/sites-available/default
    sudo /etc/init.d/nginx restart

Set up Debian repository directories:

    sudo mkdir -p /srv/repository
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

    sudo mkdir -p /etc/jenkins_jobs
    sudo tee -a /etc/jenkins_jobs/jenkins_jobs.ini >/dev/null <<EOF
    [jenkins]
    user=jenkins-job-builder
    password=$PASSWORD
    url=http://localhost:8080/
    EOF

Install Matrix Reloaded Jenkins Plugin:

    sudo wget -O /var/lib/jenkins/plugins/matrix-reloaded.hpi http://updates.jenkins-ci.org/latest/matrix-reloaded.hpi
    sudo chown jenkins:nogroup /var/lib/jenkins/plugins/matrix-reloaded.hpi

Install Build Blocker Jenkins Plugin:

    sudo wget -O /var/lib/jenkins/plugins/build-blocker-plugin.hpi http://updates.jenkins-ci.org/latest/build-blocker-plugin.hpi
    sudo chown jenkins:nogroup /var/lib/jenkins/plugins/build-blocker-plugin.hpi

Install Build-timeout Plugin:

    sudo wget -O /var/lib/jenkins/plugins/build-timeout.hpi http://updates.jenkins-ci.org/latest/build-timeout.hpi
    sudo chown jenkins:nogroup /var/lib/jenkins/plugins/build-timeout.hpi

Install groovy-label-assignment Plugin:

    sudo wget -O /var/lib/jenkins/plugins/groovy-label-assignment.hpi http://updates.jenkins-ci.org/latest/groovy-label-assignment.hpi
    sudo chown jenkins:nogroup /var/lib/jenkins/plugins/groovy-label-assignment.hpi

Adjust for usage with headless Java (if not already present):

    echo JAVA_ARGS="-Djava.awt.headless=true" | sudo tee -a /etc/default/jenkins

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
