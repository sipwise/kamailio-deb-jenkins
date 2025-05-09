def dists = ["{{ distributions| join('", "') }}"]
def parallelStagesMap

def generateStage(dist) {
    return {
        stage("trigger ${dist}") {
            build wait: false, propagate: false, job: '{{name}}-source', parameters: [string(name: 'distribution', value: "${dist}")]
        }
    }
}

pipeline {
    agent any
    stages {
        stage("generate parallel map") {
            steps {
                script {
                    parallelStagesMap = dists.collectEntries {
                        ["${it}": generateStage(it)]
                    }
                }
            }
        }
        stage('trigger parallel map') {
            steps {
                script {
                    parallel parallelStagesMap
                }
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
