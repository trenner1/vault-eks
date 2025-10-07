# Vault Enterprise on EKS - Configuration

This directory contains all configuration files for Vault Enterprise deployment.

## Structure

```
config/
├── config.yml                    # Main Vault Enterprise Helm values
├── helm-vault-raft-values.yml    # Raft HA configuration
├── cloudwatch/                   # CloudWatch logging configuration
│   └── cloudwatch-policy.json    # IAM policy for CloudWatch Logs
└── fluent-bit/                   # Fluent Bit log collector
    ├── fluent-bit-config.yaml    # Fluent Bit ConfigMap
    └── fluent-bit-daemonset.yaml # Fluent Bit DaemonSet
```

## Files

### Vault Configuration

- **config.yml** - Helm chart values for Vault Enterprise including:
  - Docker image and version
  - Enterprise license configuration
  - Storage class settings
  
- **helm-vault-raft-values.yml** - Raft storage configuration including:
  - HA settings
  - Raft cluster configuration
  - Listener settings
  - UI enablement
  - Service registration

### CloudWatch Logging

- **cloudwatch/cloudwatch-policy.json** - IAM policy granting permissions to:
  - Create log groups
  - Create log streams
  - Put log events
  - Describe log streams

### Fluent Bit

- **fluent-bit/fluent-bit-config.yaml** - ConfigMap with:
  - Input configuration (tails Vault container logs)
  - Kubernetes metadata filter
  - CloudWatch output configuration
  
- **fluent-bit/fluent-bit-daemonset.yaml** - DaemonSet deployment including:
  - Service account with IRSA annotations
  - RBAC permissions
  - Volume mounts for log access

## Customization

### Changing Vault Version

Edit `config.yml`:

```yaml
server:
  image:
    repository: "hashicorp/vault-enterprise"
    tag: "1.20.4-ent"  # Change this
```

### Adjusting Storage Size

Edit `helm-vault-raft-values.yml`:

```yaml
server:
  dataStorage:
    size: 10Gi  # Change this
```

### CloudWatch Region

Edit `fluent-bit/fluent-bit-config.yaml` and `fluent-bit/fluent-bit-daemonset.yaml`:

```yaml
env:
- name: AWS_REGION
  value: us-west-2  # Change this
```

## Security Notes

**Never commit:**
- Vault license files (`.hclic`)
- Unseal keys
- Root tokens
- Actual IAM role ARNs (use placeholders with `${VAR}` syntax)
