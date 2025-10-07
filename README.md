# Vault Enterprise on EKS

A robust, enterprise-ready infrastructure repository for quickly deploying HashiCorp Vault Enterprise with integrated Raft storage on Amazon EKS.

## Quick Start

### Automated Deployment

The fastest way to get Vault Enterprise running:

```bash
# 1. Ensure you have a Vault Enterprise license file
cp your-license.hclic vault.hclic

# 2. Install Git hooks (optional but recommended)
./scripts/setup-hooks.sh

# 3. Run the automated deployment script
./scripts/deploy-vault.sh
```

This script will:
- Check prerequisites (kubectl, helm, aws CLI)
- Add Hashicorp Helm repository
- Create namespace and license secret
- Deploy 3-node HA Vault cluster
- Initialize Vault with 5 unseal keys (threshold: 3)
- Unseal all nodes automatically
- Join nodes to Raft cluster
- Enable audit logging to stdout
- Verify cluster health

**Save your unseal keys and root token securely!** They will be in `vault-init.json`.

### Optional: CloudWatch Audit Logging

After deployment, set up centralized audit logging:

```bash
./scripts/setup-cloudwatch-logging.sh
```

### Teardown

To completely remove Vault and all data:

```bash
./scripts/teardown-vault.sh
```

**Warning:** This deletes all Vault data permanently!

## Repository Structure

```
vault-eks/
├── scripts/                      # Automation scripts
│   ├── deploy-vault.sh          # Automated deployment
│   ├── teardown-vault.sh        # Automated cleanup
│   ├── setup-cloudwatch-logging.sh # CloudWatch setup
│   ├── setup-hooks.sh           # Git hooks installer
│   └── README.md                # Scripts documentation
├── config/                       # Configuration files
│   ├── config.yml               # Vault Helm values
│   ├── helm-vault-raft-values.yml # Raft HA config
│   ├── cloudwatch/              # CloudWatch configs
│   │   └── cloudwatch-policy.json
│   ├── fluent-bit/              # Fluent Bit configs
│   │   ├── fluent-bit-config.yaml
│   │   └── fluent-bit-daemonset.yaml
│   └── README.md                # Config documentation
├── docs/                         # Documentation
│   └── cloudwatch-insights-queries.md
├── examples/                     # Example configurations
│   └── README.md
├── .githooks/                    # Git hooks
│   ├── pre-commit               # Security checks
│   └── commit-msg               # Commit format
├── .gitignore
└── README.md
```

## Prerequisites

### Required Tools

- `kubectl` - Kubernetes CLI
- `helm` - Kubernetes package manager (v3+)
- `aws` - AWS CLI (configured with credentials)
- `jq` - JSON processor (for automated deployment)
- Valid Vault Enterprise license file

### EKS Cluster Requirements

- Running EKS cluster with nodes
- StorageClass configured (e.g., `gp2` for AWS EBS)
- OIDC provider enabled (for CloudWatch logging with IRSA)
- Sufficient resources (recommended: 3 nodes, 2 CPU / 4GB RAM per node)

## What Gets Deployed

The automated deployment creates:

1. **Vault Cluster**
   - 3 StatefulSet pods (vault-0, vault-1, vault-2)
   - Integrated Raft storage for HA
   - Enterprise license activated
   - UI enabled

2. **Storage**
   - 3 Persistent Volume Claims (10GB each)
   - EBS volumes via gp2 StorageClass

3. **Networking**
   - ClusterIP service: `vault` (8200, 8201)
   - Headless service: `vault-internal` (for Raft)
   - Vault Agent Injector for sidecar injection

4. **Security**
   - TLS disabled by default (enable for production!)
   - Audit logging to stdout
   - Optional CloudWatch integration

## Manual Deployment (Advanced)

If you prefer manual control over the deployment process:

### Enable the UI

The UI is enabled by adding `ui = true` in the Vault configuration HCL in `helm-vault-raft-values.yml`:

```yaml
server:
  ha:
    raft:
      config: |
        # ... other config ...
        ui = true
```

This is already configured in the provided `helm-vault-raft-values.yml`.

### Local Access via Port-Forward (Development)

For local development and testing, use `kubectl port-forward`:

```bash
kubectl -n vault port-forward vault-0 8200:8200
```

This will forward your local port 8200 to vault-0. Access the UI at:
- **http://localhost:8200/ui/**

Login with your root token from the initialization step.

> **Note:** The port-forward command will run in the foreground. Press `Ctrl+C` to stop it, or add `&` at the end to run it in the background.

### Production Access Options

For production environments, consider one of these approaches:

1. **LoadBalancer Service:**
   Add to your values file:
   ```yaml
   server:
     service:
       type: LoadBalancer
   ```
   Then upgrade: `helm upgrade vault hashicorp/vault -f config.yml -f helm-vault-raft-values.yml`

2. **Ingress Controller:**
   Configure an Ingress resource with TLS termination (recommended for production)

3. **AWS Application Load Balancer (ALB):**
   Use the AWS Load Balancer Controller with appropriate annotations

> **Warning:** Always enable TLS before exposing Vault publicly. The current configuration has `tls_disable = "true"` which is only suitable for testing.

## 10. Additional Configuration Steps

- **Enable TLS:** Replace the `tls_disable = "true"` listener in `helm-vault-raft-values.yml` with proper certificates before production use
- **Enable Auto-Unseal:** Integrate with AWS KMS or an HSM to avoid manual unseal operations after restarts
- **Configure Auth & Secrets Engines:** Use the root token to set up auth methods (e.g., AWS IAM, Kubernetes) and your required secrets engines
- **Enable Audit Logging:** Direct audit logs to CloudWatch, S3, or another compliant destination

## 11. Git Hooks for Security and Commit Standards

This repository includes Git hooks to maintain code quality and security. The hooks are stored in `.githooks/` and must be installed locally.

### Quick Setup

Run the setup script to install the hooks:

```bash
./scripts/setup-hooks.sh
```

This will copy the hooks from `.githooks/` to `.git/hooks/` and make them executable.

### Pre-Commit Hook (Security)

The pre-commit hook scans for:
- Passwords, API keys, and secret keys in code
- AWS access keys and Vault tokens
- GitHub, Slack, and OpenAI tokens
- Large files that should use Git LFS

Files in `secrets.txt` and `*.hclic` are automatically excluded from scanning.

### Commit-Msg Hook (Conventional Commits)

Enforces the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) specification:

**Format:**
```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

**Allowed Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `perf`: Performance improvements
- `test`: Test changes
- `build`: Build system changes
- `ci`: CI/CD changes
- `chore`: Other changes
- `revert`: Revert a commit

**Examples:**
```bash
git commit -m "feat: add Vault UI configuration"
git commit -m "fix(storage): resolve PVC binding issue"
git commit -m "docs: update README with deployment steps"
git commit -m "chore: enable security pre-commit hooks"
```

### Manual Setup (Alternative)

If you prefer to install hooks manually:

```bash
cp .githooks/pre-commit .git/hooks/pre-commit
cp .githooks/commit-msg .git/hooks/commit-msg
chmod +x .git/hooks/pre-commit .git/hooks/commit-msg
```

### Bypassing Hooks (Not Recommended)

If absolutely necessary, bypass hooks with:
```bash
git commit --no-verify -m "your message"
```

## Troubleshooting Tips

### Pods Stuck in Pending State

If pods remain in `Pending` state with the error `pod has unbound immediate PersistentVolumeClaims`:

1. Check PVC status:
   ```bash
   kubectl -n vault get pvc
   ```

2. If PVCs show no `STORAGECLASS`, ensure `server.dataStorage.storageClass` is set in `config.yml`:
   ```yaml
   server:
     dataStorage:
       storageClass: gp2
   ```

3. Verify a StorageClass exists:
   ```bash
   kubectl get storageclass
   ```

4. If you need to fix the StorageClass, you must delete and recreate the deployment:
   ```bash
   helm uninstall vault -n vault
   kubectl -n vault delete pvc --all
   helm install vault hashicorp/vault -f config.yml -f helm-vault-raft-values.yml
   ```

### Enterprise License Not Recognized

If `vault read sys/health` shows `"enterprise": false`:

1. Verify the secret was created correctly with `--from-literal="license=${secret}"`:
   ```bash
   kubectl -n vault get secret vault-ent-license -o yaml
   ```

2. Ensure `config.yml` contains only:
   ```yaml
   server:
     enterpriseLicense:
       secretName: vault-ent-license
   ```
   **Do not** add `secretKey` or `extraEnvironmentVars` - the Helm chart handles this automatically.

3. Redeploy if the configuration was incorrect:
   ```bash
   helm upgrade vault hashicorp/vault -f config.yml -f helm-vault-raft-values.yml
   kubectl -n vault delete pod vault-0 vault-1 vault-2
   ```

### Additional Diagnostics

- Check pod logs: `kubectl -n vault logs vault-0`
- Describe pods: `kubectl -n vault describe pod vault-0`
- Check events: `kubectl -n vault get events --sort-by=.lastTimestamp | tail -n 20`
- Confirm PVCs are bound: `kubectl -n vault get pvc`

## 10. CloudWatch Audit Logging

Vault audit logs are crucial for security compliance and troubleshooting. This setup streams audit logs to AWS CloudWatch Logs using Fluent Bit, which handles leader election seamlessly.

### Why CloudWatch?

- **Leader Election Safe**: Logs from all pods (including after leader changes) are centralized
- **Persistent**: Logs survive pod restarts and cluster upgrades
- **Searchable**: Use CloudWatch Insights to query audit events
- **Compliance**: Meet audit retention requirements

### Setup Steps

1. **Prerequisites:**
   - EKS cluster with OIDC provider enabled
   - AWS CLI configured with appropriate permissions
   - kubectl access to your cluster

2. **Run the automated setup:**
   ```bash
   ./scripts/setup-cloudwatch-logging.sh
   ```

   The script will:
   - Create IAM policy for CloudWatch Logs access
   - Create IAM role with IRSA (IAM Roles for Service Accounts)
   - Deploy Fluent Bit DaemonSet to collect logs
   - Enable Vault audit device to stdout
   - Configure log streaming to CloudWatch

3. **Verify the setup:**
   ```bash
   # Check Fluent Bit pods
   kubectl -n vault get pods -l app=fluent-bit
   
   # Check Vault audit device
   kubectl -n vault exec -it vault-0 -- sh -c 'VAULT_TOKEN=<root-token> vault audit list'
   
   # Tail CloudWatch logs
   aws logs tail /aws/eks/vault/audit --follow
   ```

### Viewing Audit Logs

**Via AWS Console:**
1. Navigate to CloudWatch → Log groups
2. Find `/aws/eks/vault/audit`
3. Use CloudWatch Insights to query logs

**Via AWS CLI:**
```bash
# Tail logs in real-time
aws logs tail /aws/eks/vault/audit --follow

# Query recent logs
aws logs tail /aws/eks/vault/audit --since 1h

# Search for specific events
aws logs filter-log-events \
  --log-group-name /aws/eks/vault/audit \
  --filter-pattern "type=request" \
  --start-time $(date -u -d '1 hour ago' +%s)000
```

**Example CloudWatch Insights Query:**
```sql
fields @timestamp, request.path, request.operation, auth.display_name
| filter type = "request"
| sort @timestamp desc
| limit 100
```

### Manual Setup (Alternative)

If you prefer manual setup or need to customize:

1. Create IAM policy from `cloudwatch-policy.json`
2. Create IAM role with IRSA trust relationship
3. Update `fluent-bit-daemonset.yaml` with your role ARN
4. Apply manifests:
   ```bash
   kubectl apply -f fluent-bit-config.yaml
   kubectl apply -f fluent-bit-daemonset.yaml
   ```
5. Enable audit device:
   ```bash
   kubectl -n vault exec -it vault-0 -- \
     sh -c 'VAULT_TOKEN=<root-token> vault audit enable file file_path=stdout'
   ```

### Troubleshooting

- **No logs appearing**: Check Fluent Bit pods with `kubectl -n vault logs -l app=fluent-bit`
- **Permission denied**: Verify IAM role has CloudWatch permissions and trust policy is correct
- **High costs**: Adjust log retention in CloudWatch (default is indefinite)

## 11. Git Hooks Setup

