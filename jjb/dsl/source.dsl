pipeline {
    agent { label "slave:${distribution}" }
    stages {
        stage('clean workspace') {
            steps {
                sh 'rm -f ./* || true'
            }
        }
        stage('checkout code') {
            steps {
                checkout changelog: false, poll: false, scm: scmGit(branches: [[name: '*/{{ branch }}']], browser: github('{{ browser_url }}'), extensions: [cleanBeforeCheckout(deleteUntrackedNestedRepositories: true), cloneOption(noTags: false, reference: '', shallow: false), [$class: 'RelativeTargetDirectory', relativeTargetDir: 'source']], userRemoteConfigs: [[name: 'origin', refspec: '{{ refspec }}', url: '{{ repos }}']])
            }
        }
        stage('Build source') {
            environment {
                debian_dir={{ debian_dir }}
            }
            steps {
                sh '/home/admin/kamailio-deb-jenkins/scripts/jdg-generate-source'
            }
        }
        stage('store artifacts') {
            steps {
                archiveArtifacts artifacts: '*.gz,*.bz2,*.xz,*.deb,*.dsc,*.changes', fingerprint: true, followSymlinks: false
            }
        }
        stage('trigger build') {
            steps {
{%- for arch in architectures %}
                build wait: false, propagate: false, job: '{{ name }}-binaries', parameters: [string(name: 'distribution', value: "${distribution}"), string(name: 'architecture', value: '{{ arch }}')]
{%- endfor %}
            }
        }
    }
}