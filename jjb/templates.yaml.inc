- job-template:
    name: '{name}-get-code'
    project-type: pipeline
    disabled: '{obj:disabled}'
    node: built-in
    concurrent: false
    description: |
      <!-- Do NOT edit this job through the web, it is generated via jenkins-job-builder! -->
    dsl:
      !include-jinja2: dsl/get-code.dsl
    properties:
      - build-discarder:
          days-to-keep: '{logrotate_keep}'
    triggers:
      - pollscm:
          cron: '@midnight'

- job-template:
    name: '{name}-source'
    project-type: pipeline
    disabled: '{obj:disabled}'
    concurrent: true
    description: |
      Build Debian source package of {name}.
      <!-- Do NOT edit this job through the web, it is generated via jenkins-job-builder! -->
    parameters:
      - choice:
          name: distribution
          choices: '{obj:distributions}'
    dsl:
      !include-jinja2: dsl/source.dsl
    properties:
      - build-discarder:
          days-to-keep: '{logrotate_keep}'
      - copyartifact:
          projects: '{name}-binaries'

- job-template:
    name: '{name}-binaries'
    project-type: pipeline
    disabled: '{obj:disabled}'
    concurrent: true
    description: |
      Build Debian/Ubuntu binary packages of {name}.
      <!-- Do NOT edit this job through the web, it is generated via jenkins-job-builder! -->
    parameters:
      - choice:
          name: distribution
          choices: '{obj:distributions}'
      - choice:
          name: architecture
          choices: '{obj:architectures}'
      - copyartifact-build-selector:
          name: BUILD_SELECTOR
          which-build: upstream-build
          description: 'Which build from upstream to copy artifacts from'
    dsl:
      !include-jinja2: dsl/binaries.dsl
    properties:
      - build-discarder:
          days-to-keep: '{logrotate_keep}'
      - copyartifact:
          projects: '{name}-repos,{name}-piuparts'

- job-template:
    name: '{name}-repos'
    project-type: pipeline
    disabled: '{obj:disabled}'
    node: built-in
    concurrent: false
    description: |
      Repository handling for Debian packages of {name}.
      <!-- Do NOT edit this job through the web, it is generated via jenkins-job-builder! -->
    parameters:
      - choice:
          name: distribution
          choices: '{obj:distributions}'
      - choice:
          name: architecture
          choices: '{obj:architectures}'
      - copyartifact-build-selector:
          name: BUILD_SELECTOR
          which-build: upstream-build
          description: 'Which build from upstream to copy artifacts from'
    dsl:
      !include-jinja2: dsl/repos.dsl
    properties:
      - build-discarder:
          days-to-keep: '{logrotate_keep}'

- job-template:
    name: '{name}-piuparts'
    project-type: pipeline
    disabled: '{obj:disabled}'
    concurrent: true
    description: |
      Installation and upgrade tests for {name} Debian packages.
      <!-- Do NOT edit this job through the web, it is generated via jenkins-job-builder! -->
    parameters:
      - choice:
          name: distribution
          choices: '{obj:distributions}'
      - choice:
          name: architecture
          choices: '{obj:architectures}'
      - copyartifact-build-selector:
          name: BUILD_SELECTOR
          which-build: upstream-build
          description: 'Which build from upstream to copy artifacts from'
    dsl:
      !include-jinja2: dsl/piuparts.dsl
    properties:
      - build-discarder:
          days-to-keep: '{logrotate_keep}'

- view-template:
    name: '{name}'
    view-type: list
    regex: '{name}.*'
