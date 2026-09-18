# LEARNING.md — the "so what" behind each step

This project deliberately uses four separate tools where a single script
could arguably stand up the same end state faster. That's the point:
each tool exists because it's the right tool for one specific layer of
the problem, and seeing where the boundaries fall between them is most
of what's worth learning here.

## Layer 1: OpenTofu — provisioning

**Job**: does the compute resource exist, with the right size, network
access, and disk? Nothing about OpenTofu knows or cares what software
ends up running on the box.

**Core idea — declarative state diffing**: you never tell Terraform/
OpenTofu "create an EC2 instance." You describe what should exist
(`main.tf`), and it diffs that against `terraform.tfstate` (its record
of what it last created) and the real AWS API, then computes the
minimal set of create/update/destroy calls to close the gap. Change
`instance_type` from `t3.small` to `t3.medium` and re-run `tofu apply` —
it won't create a second instance, it'll show a plan to *modify* the
existing one in place (or replace it, if the change requires that —
`tofu plan` always tells you which before you commit).

**Why OpenTofu specifically, not Terraform**: HashiCorp moved Terraform
to the Business Source License (BSL) in 2023 — source-available, but
not OSI-approved open source, and it restricts building competing
commercial products on top of it. OpenTofu is the MPL-2.0-licensed fork,
now a CNCF project, with identical HCL syntax and the same provider
ecosystem. Everything here would work unchanged if you swapped the
`tofu` binary for `terraform`.

**Why we didn't have Terraform create the key pair or install
software**: two boundaries worth noticing —
- Private keys Terraform generates get written into the state file in
  plaintext. Bringing your own pre-existing key pair avoids that
  secret-leakage risk entirely.
- Terraform's `provisioner` blocks (its mechanism for running remote
  commands post-creation) are explicitly called a "last resort" in
  HashiCorp's own docs, because Terraform has no real concept of
  ongoing configuration state — it can run a script once at creation
  time, but it can't tell you three weeks later whether that
  configuration has drifted. That's Ansible's job.

## Layer 2: Ansible — configuration management

**Job**: given a server that already exists, get the right software
installed and configured on it — and stay correct if run again later.

**Core idea — idempotency**: every task in `playbook.yml` is written so
that running it five times produces the same end state as running it
once. Modules like `apt:` check current state before acting; for k3s
(no dedicated Ansible module exists) we hand-built idempotency with a
`creates:` guard on the shell task. This distinction — "did this task
change anything, or was it already satisfied?" — is what Ansible's
per-task `ok`/`changed`/`failed` output is telling you on every run,
and it's the main thing that separates configuration management from a
plain bash script.

**Core idea — agentless**: there's no persistent Ansible service running
on the EC2 instance. Every run is: SSH in, push a small Python payload,
execute it, tear it down. Nothing to install ahead of time on the
target beyond Python itself (which Ubuntu ships with).

**The `delegate_to: localhost` task** (pulling the kubeconfig) is worth
sitting with — it's a reminder that an Ansible "play" isn't strictly
"do N things on the remote host." Individual tasks can target other
hosts, including your own control machine, mid-playbook.

## Layer 3: k3s — the Kubernetes distribution

**Job**: be an actual, conformant Kubernetes API server your app
manifests can target — just packaged small enough to fit a 2GB-RAM box.

Full kubeadm-built clusters run separate processes for the API server,
scheduler, controller-manager, and etcd (a distributed key-value store
with real resource appetite). k3s bundles all control-plane components
into one binary and defaults to SQLite instead of etcd for a single-node
setup. The tradeoff is real (etcd's distributed consensus matters once
you have multiple control-plane nodes, which is out of scope for a
1-node lab) but the *API surface* is identical — every manifest in
`app/k8s/` would work verbatim against EKS, GKE, or a kubeadm cluster.

## Layer 4: ArgoCD — GitOps continuous delivery

**Job**: keep the cluster's actual state matching what git says it
should be, continuously, without a human running `kubectl apply`.

**Core idea — pull, not push**: CI (GitHub Actions) never talks to your
cluster directly — it has no credentials for it and couldn't reach it
even if it tried. Instead, ArgoCD (running *inside* the cluster) polls
your git repo and pulls changes in. This inverts the traditional CD
model where a pipeline pushes a deploy command to a target environment,
and it means your cluster never needs an inbound endpoint exposed to
your CI system — a real reduction in attack surface, not just a
buzzword.

**`selfHeal: true`** is the sharpest illustration of what "GitOps"
actually promises: if you `kubectl edit` a live resource by hand,
ArgoCD's next reconcile loop reverts it back to match git. The cluster
structurally can't stay out of sync with git for long, even by
accident — git isn't just *a* record of desired state, it's positioned
as the *only* one that matters.

## Layer 5: GitHub Actions — CI

**Job**: is the code good, and what image did we produce from it? Stops
there — deliberately knows nothing about deployment.

**Why the git SHA as the image tag, never `latest`**: `latest` is a
moving target — re-pulling it tomorrow gives you a different image than
what's running today, and you can't tell from a running pod which code
is actually inside it. Tagging with the immutable commit SHA means
`app/k8s/deployment.yaml`'s git history *is* your deploy history —
`git log -p app/k8s/deployment.yaml` shows you every version that's
ever been shipped and when.

**Why CI commits back to the repo instead of deploying directly**: this
is the mechanical link between the CI half and the CD half. CI's last
action is a git commit, not a kubectl command — ArgoCD is what notices
that commit and acts on it. If you deleted ArgoCD entirely, this
workflow would keep running successfully (building images, committing
manifest updates) and nothing would ever actually deploy — which is a
useful way to see, concretely, that CI and CD are genuinely separate
concerns being handled by separate tools.

## Where this connects to things covered earlier

- The Deployment's `replicas: 2` is the "scale by adding more pods, not
  more apps per pod" pattern.
- ArgoCD's own architecture is the sidecar/control-plane split covered
  earlier for Istio: `argocd-server` and friends are just regular pods
  in the `argocd` namespace, same as any app — nothing about "control
  plane" software is special-cased by Kubernetes itself.
- The security group in `main.tf` scoped to `my_ip_cidr` is the same
  "My IP, not 0.0.0.0/0" principle from the manual console setup,
  just expressed as code.
- EBS encryption (`encrypted = true` in `main.tf`) is the same free,
  no-downside setting from the manual console checkbox, carried into
  Terraform.
