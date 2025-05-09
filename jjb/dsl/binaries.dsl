pipeline {
    agent { label "slave:${distribution}" }
    stages {
        stage('clean workspace') {
            steps {
                deleteDir()
            }
        }
        stage('copy artifacts') {
            steps {
                copyArtifacts filter: '*.gz,*.bz2,*.xz,*.dsc,*.changes', fingerprintArtifacts: true, projectName: '{{ name }}-source', selector: buildParameter('BUILD_SELECTOR')
            }
        }
        stage('Build') {
            steps {
                environment {
                    {%- if debian_profiles is defined %}
                    DEB_BUILD_PROFILES="$({{ debian_profiles }})"
                    {%- endif %}
                }
                sh '/home/admin/kamailio-deb-jenkins/scripts/jdg-build-package'
            }
            post {
                success {
                    sh 'mkdir -p report'
                    sh '/usr/bin/lintian-junit-report --skip-lintian --filename *.lintian.txt *.lintian.txt > report/lintian.xml'
                    sh 'mkdir -p report adt'
                    sh 'touch adt/summary # do not fail if no autopkgtest run took place'
                    sh '/usr/bin/adtsummary_tap adt/summary > report/autopkgtest.tap'
                }
            }
        }
        stage('store artifacts') {
            steps {
                archiveArtifacts artifacts: '**/*.gz,**/*.bz2,**/*.xz,**/*.deb,**/*.ddeb,**/*.dsc,**/*.changes,**/*.buildinfo,**/*lintian.txt', fingerprint: true, followSymlinks: false
            }
        }
    }
    post {
        success {
            build wait: false, propagate: false, job: '{{ name }}-repos', parameters: [string(name: 'distribution', value: "${distribution}"), string(name: 'architecture', value: "${architecture}")]
        }
    }
}
