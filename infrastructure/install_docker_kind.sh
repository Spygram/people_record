#!/bin/bash
# Add Docker's official GPG key:
sudo apt update
# Added -y flag
sudo apt install ca-certificates curl -y
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update

# Added -y flag so apt installs everything completely unattended
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

sudo systemctl start docker
sudo systemctl enable docker

# CRITICAL: Adds your SSH deployment user to the docker daemon group permission scope
sudo usermod -aG docker ubuntu

wget -c https://github.com/kubernetes-sigs/kind/releases/download/v0.32.0/kind-linux-amd64

sudo mv kind-linux-amd64 /usr/local/bin/kind
sudo chmod +x /usr/local/bin/kind
kind --version

cat > kind-config.yaml <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
# One control plane node and three "workers".
#
# While these will not add more real compute capacity and
# have limited isolation, this can be useful for testing
# rolling updates etc.
#
# The API-server and other control plane components will be
# on the control-plane node.
#
# You probably don't need this unless you are testing Kubernetes itself.
nodes:
- role: control-plane
- role: worker
- role: worker
- role: worker
EOF

kind create cluster --config kind-config.yaml

#Install Kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo mv kubectl /usr/local/bin/kubectl
sudo chmod +x /usr/local/bin/kubectl
kubectl --version


