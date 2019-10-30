podTemplate(yaml: """
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: kaniko
    image: gcr.io/kaniko-project/executor:debug-539ddefcae3fd6b411a95982a830d987f4214251
    imagePullPolicy: Always
    command:
    - /busybox/cat
    tty: true
    volumeMounts:
      - name: jenkins-docker-cfg
        mountPath: /kaniko/.docker
  - name: golang
    image: golang:1.8.0
    command: ['cat']
    tty: true
  volumes:
  - name: jenkins-docker-cfg
    projected:
      sources:
      - secret:
          name: regcred
          items:
            - key: .dockerconfigjson
              path: config.json
"""
  ) 
    node(POD_LABEL) {
      stage('Build with Kaniko') {
    		git 'https://github.com/jenkinsci/docker-jnlp-slave.git'
    		container('kaniko') {
      		sh '/kaniko/executor -f `pwd`/Dockerfile -c `pwd` --insecure --skip-tls-verify --cache=true --destination=mydockerregistry:5000/myorg/myimage'
	      }
	    }

      stage('Get a Golang project') {
          git url: 'https://github.com/hashicorp/terraform.git'
          container('golang') {
              stage('Build a Go project') {
                  sh """
                  mkdir -p /go/src/github.com/hashicorp
                  ln -s `pwd` /go/src/github.com/hashicorp/terraform
                  cd /go/src/github.com/hashicorp/terraform && make core-dev
                  """
              		}
	          		}
				      }
				    } 