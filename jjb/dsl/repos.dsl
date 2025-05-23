pipeline {
    agent { label 'built-in' }
    stages {
        stage("Initialization") {
            steps {
                buildName "#${BUILD_NUMBER} ${distribution}:${architecture}"
            }
        }
        stage('copy artifacts') {
            steps {
                deleteDir()
                copyArtifacts filter: '*', fingerprintArtifacts: true, projectName: '{{ name }}-binaries', target: 'binaries', selector: buildParameter('BUILD_SELECTOR')
            }
        }
        stage('repository') {
            environment {
              ARCHITECTURES="{{ architectures|join(' ')}} source"
            }
            steps {
                sh "/home/admin/kamailio-deb-jenkins/scripts/jdg-repository"
            }
        }
        stage('store artifacts') {
            steps {
                archiveArtifacts artifacts: '**/*.dsc,**/*.changes', fingerprint: true, followSymlinks: false
            }
        }
        stage('trigger piuparts') {
            steps {
                build wait: false, propagate: false, job: '{{ name }}-piuparts', parameters: [string(name: 'distribution', value: "${distribution}"), string(name: 'architecture', value: "${architecture}")]
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
