# Deployment Guide

Provisioning the infrastructure, deploying the application, and tearing it all down.

---

## Prerequisites

| Tool | Version | Purpose |
| --- | --- | --- |
| Terraform | ≥ 1.5 | Provisioning |
| AWS CLI | v2, configured | Credentials for the AWS provider |
| Docker | ≥ 24 | Building images |
| `kubectl` | ≥ 1.28 | Applying manifests |
| Node.js | 20.x | Running the API locally |

You also need:

- An AWS account with permission to create VPC, EC2 and RDS resources.
- The S3 bucket `3-tier-project-statefile` in `us-east-1` (or edit the backend block in `infrastructure/provider.tf`).
- An IAM instance profile named `LabInstanceProfile` — looked up by `data.tf`, not created by this stack.
- A Docker Hub account if you intend to publish your own images.
- Control over a domain if you want the ingress hostnames to resolve.

---

## Stage 1 — Provision the infrastructure

```bash
cd infrastructure
terraform init      # configures the encrypted S3 backend
terraform plan  -var="target_env=dev"
terraform apply -var="target_env=dev"
```

`target_env` is validated against `dev`, `stage` and `prod`; anything else fails the plan. Every resource is name-prefixed with it, so multiple environments coexist cleanly.

### What gets created

| Resource | Details |
| --- | --- |
| VPC | `10.0.0.0/16`, DNS hostnames and support enabled |
| Internet Gateway | Attached to the VPC |
| Public subnet | `10.0.1.0/24`, auto-assign public IP, routed to the IGW |
| Private subnets | `10.0.10.0/24`, `10.0.11.0/24` across two AZs, no internet route |
| DB subnet group | Spans both private subnets |
| Security groups | `jenkins-sg`, `kind-cluster-sg`, `rds-sg` |
| Key pair | ED25519, generated at apply time |
| Jenkins EC2 | `t2.micro`, Ubuntu 24.04, JDK 21 + Jenkins installed by provisioner |
| kind EC2 | `t2.large`, 32 GB gp3, Docker + kind + kubectl via user data |
| RDS | PostgreSQL 18.3, `db.t3.micro`, 20 GB gp3, private |

### Tunable variables

| Variable | Default | Notes |
| --- | --- | --- |
| `aws_region` | `us-east-1` | |
| `vpc_cidr` | `10.0.0.0/16` | |
| `public_subnet_cidrs` | `10.0.1.0/24` | Single string, not a list |
| `private_subnet_cidrs` | `["10.0.10.0/24","10.0.11.0/24"]` | Subnet count derives from list length |
| `instance_type` | `t2.micro` | Jenkins host only; the cluster node is pinned to `t2.large` |
| `target_env` | *(required)* | Must be `dev`, `stage` or `prod` |
| `db_username` | `dbadmin` | |
| `db_name` | `pplmgtdb` | |

### Outputs on disk

Two files are written locally and are **git-ignored**:

- `<target_env>-key.pem` — the private SSH key, mode `0600`
- `backend/db-config.json` — RDS host, port, database, username and generated password

---

## Stage 2 — Bootstrap Jenkins

The `install_jenkins.sh` provisioner waits 60 seconds for cloud-init, then installs OpenJDK 21 and Jenkins from the Debian stable repository.

```bash
ssh -i dev-key.pem ubuntu@<jenkins_public_ip>
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

Open `http://<jenkins_public_ip>:8080`, unlock with that password, install the suggested plugins, and create an admin user.

### Credentials to add

| ID | Kind | Used by |
| --- | --- | --- |
| `dockerhub_credential` | Username with password | Both build pipelines |
| `appserverkey` | SSH username with private key | Orchestrator deploy stage |

### Jobs to create

| Job name | Pipeline script from SCM |
| --- | --- |
| `backend_pipeline` | `backend/Jenkinsfile` |
| `frontend_pipeline` | `public/Jenkinsfile` |
| Orchestrator (any name) | `Jenkinsfile` (root) |

The child job names are referenced literally by the orchestrator's `build job:` steps, so they must match exactly. Set `APP_SERVER` in the root `Jenkinsfile` to the private IP of your deployment target.

Full details in [CICD.md](CICD.md).

---

## Stage 3 — Deploy

Two supported paths. Pick one.

### Path A — Kubernetes on kind (primary)

The `install_docker_kind.sh` user data script has already installed Docker, `kind` v0.32.0 and `kubectl`, and created a four-node cluster (one control plane, three workers).

```bash
ssh -i dev-key.pem ubuntu@<kind_cluster_public_ip>
kubectl get nodes          # expect 4 Ready
```

Update the connection details before applying. In `k8s/configmap.yaml` set `DB_HOST` to your RDS endpoint:

```bash
terraform -chdir=infrastructure output   # or read backend/db-config.json
```

In `k8s/configsecret.yaml` the values are base64-encoded. Generate your own:

```bash
echo -n 'dbadmin'        | base64
echo -n 'your-password'  | base64
```

Then apply, controller first:

```bash
kubectl apply -f k8s/nginx-ingresscontroller.yaml
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s

kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/configsecret.yaml
kubectl apply -f k8s/backend.yaml
kubectl apply -f k8s/frontend.yaml
```

Verify:

```bash
kubectl get pods,svc,ingress
kubectl logs deploy/backend-deployment | grep "Database initialized"
```

You are looking for `✅ Database initialized (person table ready)` in the backend logs — that confirms the pod reached RDS through the security group chain.

#### Exposing kind to the outside world

`kind` runs the cluster inside Docker on the EC2 host, so the ingress controller's port must be reachable from the host's network interface. Either create the cluster with `extraPortMappings` for ports 80/443 on the control-plane node, or forward from the host:

```bash
kubectl port-forward --address 0.0.0.0 -n ingress-nginx svc/ingress-nginx-controller 80:80
```

`kind-cluster-sg` already permits inbound `80` and `3000` from anywhere.

### Path B — Docker Compose (single host)

```bash
scp -i dev-key.pem docker-compose-deploy.yaml ubuntu@<app_server>:~/docker-compose.yaml
scp -i dev-key.pem .env ubuntu@<app_server>:~/.env

ssh -i dev-key.pem ubuntu@<app_server>
docker compose pull
docker compose up -d --remove-orphans
```

The `.env` file must supply:

```bash
DB_HOST=<RDS endpoint>
DB_PORT=5432
DB_USER=dbadmin
DB_PASSWORD=<generated password>
DB_NAME=postgres

BACKEND_VERSION=latest
FRONTEND_VERSION=latest
APP_PORT=3000
```

Both services join a bridge network with `restart: always`; the frontend `depends_on` the backend. This is exactly what the orchestrator pipeline automates.

---

## Stage 4 — DNS

Point two A records at the public IP of the cluster node:

| Record | Type | Value |
| --- | --- | --- |
| `record.sujandongol.com.np` | A | `<kind_cluster_public_ip>` |
| `api.sujandongol.com.np` | A | `<kind_cluster_public_ip>` |

Both hostnames hit the same ingress controller, which routes on the `Host` header. If you use different domains, update the `host:` field in `k8s/backend.yaml` and `k8s/frontend.yaml`, and the `API_BASE` constant at the top of the `<script>` block in `public/index.html`.

Verify end to end:

```bash
curl -H "Host: api.sujandongol.com.np" http://<public_ip>/people
```

---

## Verification checklist

| Check | Command | Expected |
| --- | --- | --- |
| Nodes ready | `kubectl get nodes` | 4 × `Ready` |
| Pods running | `kubectl get pods` | `backend-deployment-*`, `frontend-deployment-*` Running |
| DB reachable | `kubectl logs deploy/backend-deployment` | `✅ Database initialized` |
| Ingress bound | `kubectl get ingress` | Both show an address |
| API responds | `curl http://api.<domain>/people` | `[]` or a JSON array |
| UI loads | Browse `http://record.<domain>` | Form and table render |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Backend logs `❌ Database connection error` repeatedly | `rds-sg` does not allow the cluster SG, or `DB_HOST` is wrong | Confirm the SG rule references `kind-cluster-sg`; re-check the ConfigMap endpoint |
| Pod restarts after ~30 s | All ten DB retries exhausted, process exits `1` | Same as above — it is a connectivity issue, not an app bug |
| `502 Bad Gateway` from ingress | Service has no ready endpoints | `kubectl get endpoints backend-service` — should list a pod IP |
| Browser shows CORS errors | `API_BASE` in `index.html` does not match the API host | Update the constant and rebuild the frontend image |
| `terraform apply` fails on IAM profile | `LabInstanceProfile` does not exist | Create it or edit `data.tf` |
| Jenkins deploy stage cannot SSH | `appserverkey` missing, or `APP_SERVER` IP is stale | Re-add the credential; confirm the private IP |
| `ImagePullBackOff` | Image not pushed, or repository is private | Check Docker Hub; add an `imagePullSecret` if private |

---

## Teardown

```bash
# Application
kubectl delete -f k8s/frontend.yaml -f k8s/backend.yaml \
                 -f k8s/configsecret.yaml -f k8s/configmap.yaml
kubectl delete -f k8s/nginx-ingresscontroller.yaml

# Infrastructure
cd infrastructure
terraform destroy -var="target_env=dev"
```

`skip_final_snapshot = true` on the RDS instance means **the database is deleted with no snapshot**. That is intentional for a demo environment — set it to `false` before running this anywhere you care about the data.

Remember to remove the local `dev-key.pem` and `backend/db-config.json` afterwards.
