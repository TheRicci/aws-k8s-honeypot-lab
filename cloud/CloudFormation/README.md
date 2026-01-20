# Honeylab – AWS EKS Infrastructure (CloudFormation)

This repository contains the **AWS CloudFormation-based infrastructure** for the Honeylab project.

The goal of this layer is to provision **cloud infrastructure only**:
- Networking (VPC, subnets)
- Kubernetes control plane (EKS)
- Compute resources (EC2 node groups)
- Container registry (ECR)
- IAM roles and permissions

Application workloads (honeypot, proxy, IDS, SIEM) are **not** deployed here.  
They are handled separately via Kubernetes manifests.

---

## Project Structure

```text
aws-honeylab-cloudformation/
├── cloudformation/   # AWS infrastructure (CloudFormation)
│   ├── 00-vpc.yaml
│   ├── 01-eks.yaml
│   ├── 02-nodegroups.yaml
│   └── 03-ecr.yaml
├── k8s/              # Kubernetes manifests (shared with Terraform version)
└── README.md