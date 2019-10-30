podTemplate(yaml: """
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: docker
    image: docker:1.11
    command: ['cat']
    tty: true
    volumeMounts:
    - name: dockersock
      mountPath: /var/run/docker.sock
  - name: golang
    image: golang:1.8.0
    command: ['cat']
    tty: true
  volumes:
  - name: dockersock
    hostPath:
      path: /var/run/docker.sock
"""
  ) {
	  def image = "jenkins/jnlp-slave"
    node(POD_LABEL) {
      stage('Build Docker image') {
      	git 'https://github.com/jenkinsci/docker-jnlp-slave.git'
      	container('docker') {
        	sh "docker build -t ${image} ."
		      }
		    }
      stage('Get a Golang project') {
          git url: 'https://github.com/hashicorp/terraform.git'
          container('golang') {
              stage('Build a Go project') {
                  sh """
                  mkdir -p /go/src/github.com/hashicorp
                  ln -s `pwd` /go/src/github.com/hashicorp/terraform
                  cd /go/src/github.com/hashicorp/terraform && make fmt && make bin
                  """
              		}
	          		}
							}
						}
					}