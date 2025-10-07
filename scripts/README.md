# Scripts

Automation scripts for deploying, managing, and tearing down Vault Enterprise on EKS.

## Available Scripts

### 🚀 deploy-vault.sh

**Purpose:** Automated end-to-end deployment of Vault Enterprise

**Usage:**
```bash
./scripts/deploy-vault.sh
```

**What it does:**
1. Checks prerequisites (kubectl, helm, aws, jq)
2. Adds HashiCorp Helm repository
3. Creates vault namespace
4. Creates license secret from `vault.hclic`
5. Deploys Vault via Helm
6. Waits for pods to be ready
7. Initializes Vault (5 keys, threshold 3)
8. Unseals all 3 nodes
9. Joins nodes to Raft cluster
10. Enables audit logging
11. Verifies cluster health

**Output:** Creates `vault-init.json` with unseal keys and root token (⚠️ **secure this file!**)

**Prerequisites:**
- Valid `vault.hclic` in root directory
- EKS cluster accessible via kubectl
- Sufficient cluster resources

---

### 🗑️ teardown-vault.sh

**Purpose:** Complete cleanup of Vault deployment

**Usage:**
```bash
./scripts/teardown-vault.sh
```

**What it does:**
1. Confirms deletion (requires typing "yes")
2. Deletes Helm release
3. Deletes Fluent Bit DaemonSet
4. Deletes all PVCs (⚠️ **data loss!**)
5. Deletes namespace
6. Cleans up local files
7. Optionally deletes IAM resources

**Deletes:**
- Vault Helm release
- All Vault pods and services
- Persistent volumes and data
- Fluent Bit resources
- Namespace
- (Optional) IAM policies and roles

---

### 📊 setup-cloudwatch-logging.sh

**Purpose:** Configure CloudWatch audit log streaming

**Usage:**
```bash
./scripts/setup-cloudwatch-logging.sh
```

**What it does:**
1. Gets AWS account ID and region
2. Prompts for EKS cluster name
3. Creates IAM policy for CloudWatch Logs
4. Creates IAM role with IRSA trust relationship
5. Deploys Fluent Bit DaemonSet
6. Provides instructions for enabling audit device

**Prerequisites:**
- AWS CLI configured with admin permissions
- EKS cluster with OIDC provider enabled
- Vault already deployed

**Output:**
- IAM policy: `VaultCloudWatchLogsPolicy`
- IAM role: `VaultFluentBitRole`
- Fluent Bit DaemonSet running
- Logs stream to: `/aws/eks/vault/audit`

---

### 🔧 setup-hooks.sh

**Purpose:** Install Git hooks for repository security

**Usage:**
```bash
./scripts/setup-hooks.sh
```

**What it does:**
1. Copies hooks from `.githooks/` to `.git/hooks/`
2. Makes hooks executable

**Hooks installed:**
- **pre-commit**: Scans for secrets before committing
- **commit-msg**: Enforces conventional commit format

**Note:** Run this after cloning the repository to enable security checks.

---

## Script Development

### Adding New Scripts

When creating new scripts:

1. **Use bash with set -e** for error handling
2. **Add colored output** using existing color variables
3. **Check prerequisites** at the start
4. **Add helpful messages** explaining each step
5. **Make it idempotent** where possible
6. **Document in this README**

### Example Template

```bash
#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Your script logic here
```

### Testing

Always test scripts in a non-production environment first:

```bash
# Test deployment
./scripts/deploy-vault.sh

# Verify
kubectl -n vault get pods

# Test teardown
./scripts/teardown-vault.sh
```

## Troubleshooting

### Script Permissions

If you get "Permission denied":
```bash
chmod +x scripts/*.sh
```

### Path Issues

Scripts reference config files using relative paths. Always run from repository root:
```bash
# Wrong
cd scripts && ./deploy-vault.sh

# Correct
./scripts/deploy-vault.sh
```

### Missing Dependencies

Install required tools:
```bash
# macOS
brew install kubectl helm awscli jq

# Linux
apt-get install -y kubectl helm awscli jq
```
