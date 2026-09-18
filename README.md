# k8s-cicd-lab

A hands-on lab that provisions a Kubernetes cluster with Terraform (via
its open-source fork, OpenTofu), configures it with Ansible, deploys
ArgoCD for GitOps continuous delivery, and wires up a GitHub Actions
CI pipeline that builds and ships a small app through the whole chain.

Read `LEARNING.md` alongside this file — it explains *why* each tool
does what it does, not just the commands. This README is the run order;
LEARNING.md is the "so what."

## Stack (all open source)

| Concern | Tool |
|---|---|
| Provisioning (create the VM) | OpenTofu (Terraform's open-source fork) |
| Configuration management | Ansible |
| Kubernetes distribution | k3s (lightweight, CNCF-certified) |
| GitOps / continuous delivery | ArgoCD |
| Continuous integration | GitHub Actions |
| Image registry | GHCR (GitHub Container Registry) |

## Prerequisites

- An AWS account with an existing EC2 key pair (you already have
  `jenops_key_pair.pem` in `~/.ssh/` from the minikube project)
- `tofu` (or `terraform`) installed locally: https://opentofu.org/docs/intro/install/
- `ansible` installed locally: `pip install ansible` or `brew install ansible`
- A GitHub account, and this project pushed to your own repo (fork it or
  copy it into a new repo — ArgoCD and CI both need a real repo URL)
- Docker Desktop is NOT required locally — GitHub Actions builds the
  image for you in the cloud

## Step 1 — Provision the EC2 instance with OpenTofu

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set key_pair_name and my_ip_cidr (curl -s ifconfig.me)

tofu init      # downloads the AWS provider plugin
tofu plan      # shows what WOULD be created — read this before apply
tofu apply     # actually creates the security group + EC2 instance
```

When it finishes, note the `public_ip` output. You'll need it next.

## Step 2 — Configure the instance with Ansible

```bash
cd ../ansible

# generate inventory.ini from Terraform's output instead of copy-pasting:
echo "[k3s_node]
$(cd ../terraform && tofu output -raw public_ip) ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/jenops_key_pair.pem

[k3s_node:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new'" > inventory.ini

ansible-playbook playbook.yml
```

This installs k3s, waits for the node to be Ready, pulls a working
`kubeconfig.yaml` back into the project root, and installs ArgoCD into
the cluster. It'll take a few minutes — mostly waiting on ArgoCD's
Deployment to roll out.

Use the kubeconfig it produced for every command below:

```bash
export KUBECONFIG=$(pwd)/../kubeconfig.yaml
kubectl get nodes        # should show one Ready node
kubectl -n argocd get pods   # ArgoCD's own pods
```

## Step 3 — Push this project to your own GitHub repo

Before ArgoCD or CI can do anything, they both need a real repo to point
at:

```bash
cd ..
git init
git add .
git commit -m "initial commit"
gh repo create k8s-cicd-lab --public --source=. --push
# or create the repo in the GitHub UI and add it as a remote manually
```

Then edit two placeholders to match your real GitHub username:
- `app/k8s/deployment.yaml` → the `image:` line
- `argocd/application.yaml` → `spec.source.repoURL`

Commit and push those edits too.

## Step 4 — Point ArgoCD at your repo

```bash
kubectl apply -f argocd/application.yaml
kubectl -n argocd get application hello-app   # should show "Missing" or
                                               # "OutOfSync" briefly, then
                                               # "Synced" once it deploys
```

To see the ArgoCD UI itself:

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
# then open https://localhost:8080 in a browser (self-signed cert warning
# is expected — click through it)
# username: admin
# password: kubectl -n argocd get secret argocd-initial-admin-secret \
#             -o jsonpath='{.data.password}' | base64 -d
```

## Step 5 — Trigger the CI/CD loop for real

Make any visible change to the app, e.g. edit the message string in
`app/main.py`, then:

```bash
git add app/main.py
git commit -m "tweak the greeting"
git push
```

Watch it flow end to end:
1. GitHub Actions tab in your repo — the workflow builds and pushes an
   image, then commits an updated `app/k8s/deployment.yaml`
2. `kubectl -n argocd get application hello-app` — flips to `OutOfSync`
   then back to `Synced` within ~3 minutes (ArgoCD's default poll
   interval) as it picks up that commit
3. `curl http://<public_ip>:30080/version` — should show the new git
   SHA once the rollout finishes

That full loop — you push code, and a running pod changes without you
ever typing `kubectl apply` — is the thing this whole project exists to
let you experience firsthand, not just read about.

## Tearing it down

Order matters — reverse of how you built it:

```bash
cd terraform
tofu destroy   # deletes the EC2 instance + security group, stops billing
```

Nothing else needs manual cleanup — GHCR images are free to leave, and
your GitHub repo is just files.

## Troubleshooting

- **Ansible SSH fails immediately after `tofu apply`**: the instance
  needs ~30-60 seconds to finish booting and start sshd. Wait and retry.
- **`ansible-playbook` fails on the k3s wait-for-Ready task**: usually
  means k3s is still starting; the `until`/`retries` loop should absorb
  this, but if it still fails after 100 seconds, SSH in manually and run
  `sudo k3s kubectl get nodes` to see the real error.
- **ArgoCD Application stuck on `Unknown` or won't sync**: almost always
  means `repoURL` in `argocd/application.yaml` doesn't match your actual
  repo, or the repo is private (ArgoCD needs a credential to read
  private repos — out of scope for this lab; keep the repo public, or
  see ArgoCD's docs on repo credentials).
- **`/version` doesn't show the new SHA after a push**: check ArgoCD's
  sync status first — it polls every ~3 minutes by default, it isn't
  instant. Force it early with `kubectl -n argocd patch application
  hello-app --type merge -p '{"operation":{"sync":{}}}'` if you don't
  want to wait.
