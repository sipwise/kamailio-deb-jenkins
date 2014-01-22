README for kamailio-deb-jenkins
===============================

This repository provides configuration and scripts as used by the server
for building Debian packages for the [Kamailio project](http://www.kamailio.org/).

Development of this setup is sponsored by [Sipwise](http://www.sipwise.com/).


Involved Software
-----------------

* [Debian](http://www.debian.org/) (version 7.3, amd64)
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
    # for cowbuilder/pbuilder/... instruction:
    Defaults  env_keep+="release branch distribution JOB_NAME"
    EOF

Grab a copy of this repository:

    git clone https://github.com/sipwise/kamailio-deb-jenkins.git /home/admin/kamailio-deb-jenkins

Adopt pbuilder for usage with building for Ubuntu:

    sudo cp /home/admin/kamailio-deb-jenkins/pbuilder/pbuilderrc /etc/jenkins/pbuilderrc

Deploy nginx as proxy for Jenkins:

    sudo apt-get -y install nginx
    sudo openssl req -days 3650 -nodes -new -x509 -keyout /etc/ssl/private/server.key -out /etc/ssl/private/server.cert
    sudo cp /home/admin/kamailio-deb-jenkins/nginx/default /etc/nginx/sites-available/default
    sudo /etc/init.d/nginx restart

Set up jenkins-job-builder:

    sudo dpkg -i /home/admin/kamailio-deb-jenkins/debs/python-jenkins*deb
    sudo dpkg -i /home/admin/kamailio-deb-jenkins/debs/jenkins-job-builder*.deb
    sudo tee -a /etc/jenkins_jobs/jenkins_jobs2.ini >/dev/null <<EOF
    [jenkins]
    user=jenkins-job-builder
    password=$PASSWORD
    url=http://localhost:8080/
    EOF

Generate according Jenkins jobs:

    cd /home/admin/kamailio-deb-jenkins/jjb
    make


Questions?
----------

For Jenkins/Build environment related questions contact Michael Prokop (mprokop (at) sipwise dot com),
for Kamailio (packaging) related questions contact Victor Seva (vseva (at) sipwise dot com).
