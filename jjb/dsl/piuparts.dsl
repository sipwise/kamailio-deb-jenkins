pipeline {
    agent { label "slave:${distribution}" }
    stages {
        stage("Initialization") {
            steps {
                buildName "#${BUILD_NUMBER} ${distribution}:${architecture}"
            }
        }
        stage('copy artifacts') {
            steps {
                deleteDir()
                copyArtifacts filter: '*.deb', fingerprintArtifacts: true, projectName: '{{ name }}-binaries', target: 'artifacts', selector: buildParameter('BUILD_SELECTOR')
            }
        }
        stage('piuparts run') {
            steps {
                sh "/home/admin/kamailio-deb-jenkins/scripts/jdg-piuparts"
            }
        }
        stage('store artifacts') {
            steps {
                archiveArtifacts artifacts: 'piuparts.*', fingerprint: true, followSymlinks: false
            }
        }
    }
    post {
        failure {
            emailext body: '{{ email_body }}',
                    to: '{{ email }}',
                    subject: 'Build failed in Jenkins: $PROJECT_NAME - #$BUILD_NUMBER'
        }
    }
}
