# Vault Enterprise on EKS

This guide captures the steps for deploying HashiCorp Vault Enterprise with integrated Raft storage on an Amazon EKS cluster u## 9. Access the Vault UI

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

This repository includes Git hooks to maintain code quality and security:

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

### Setup Hooks (Already Configured)

The hooks are already in `.git/hooks/` and executable. If you need to reinstall them:

```bash
chmod +x .git/hooks/pre-commit
chmod +x .git/hooks/commit-msg
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
- Confirm PVCs are bound: `kubectl -n vault get pvc` values in `config.yml` and `helm-vault-raft-values.yml`.

## Prerequisites

- `aws` CLI configured with access to the target EKS cluster
- `kubectl` installed and pointing at the cluster context
- `helm` v3 installed with the HashiCorp chart repository added
- Vault Enterprise license file (`vault.hclic`) ready
- EKS cluster with a StorageClass available (e.g., `gp2` for EBS volumes)

## 1. Target the EKS Cluster

```bash
aws eks update-kubeconfig --region <region> --name <cluster-name>
kubectl config current-context
```

## 2. Add/Update the Helm Repository

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
```

## 3. Create the Namespace and License Secret

Create the namespace:

```bash
kubectl create namespace vault
```

Create the license secret using the contents of your license file:

```bash
secret=$(cat vault.hclic)
kubectl -n vault create secret generic vault-ent-license --from-literal="license=${secret}"
```

Verify the secret exists:

```bash
kubectl -n vault get secret vault-ent-license
```

> **Important:** The secret must be created with `--from-literal="license=${secret}"` format. The Helm chart will automatically mount this and configure Vault Enterprise.

## 4. Verify StorageClass

Check that your EKS cluster has a StorageClass available:

```bash
kubectl get storageclass
```

You should see at least one StorageClass (e.g., `gp2`). Note the name for use in `config.yml`.

## 5. Deploy Vault with Helm

Install Vault Enterprise with the configuration files:

```bash
helm install vault hashicorp/vault \
  --namespace vault \
  --create-namespace \
  -f config.yml \
  -f helm-vault-raft-values.yml
```

Watch the pods start:

```bash
kubectl -n vault get pods -w
```

Wait for the pods to reach `Running` state (they will show `0/1` ready until initialized and unsealed).

Wait for the pods to reach `Running` state (they will show `0/1` ready until initialized and unsealed).

## 6. Initialize and Unseal Vault

Initialize Vault on the first pod (store the unseal keys and root token safely):

```bash
kubectl -n vault exec -it vault-0 -- vault operator init -key-shares=5 -key-threshold=3
```

> **Critical:** Save the 5 unseal keys and root token in a secure location. You'll need at least 3 keys to unseal Vault after any restart.

Unseal vault-0 using any 3 of the 5 unseal keys:

```bash
kubectl -n vault exec -it vault-0 -- vault operator unseal <KEY-1>
kubectl -n vault exec -it vault-0 -- vault operator unseal <KEY-2>
kubectl -n vault exec -it vault-0 -- vault operator unseal <KEY-3>
```

After the third unseal command, vault-0 will show `Sealed: false` and become the active Raft leader.

## 7. Join Additional Nodes to Raft Cluster

Join vault-1 and vault-2 to the Raft cluster:

```bash
kubectl -n vault exec -it vault-1 -- vault operator raft join http://vault-0.vault-internal:8200
kubectl -n vault exec -it vault-2 -- vault operator raft join http://vault-0.vault-internal:8200
```

Unseal each of the joined nodes (use the same 3 keys from initialization):

```bash
# Unseal vault-1
kubectl -n vault exec -it vault-1 -- vault operator unseal <KEY-1>
kubectl -n vault exec -it vault-1 -- vault operator unseal <KEY-2>
kubectl -n vault exec -it vault-1 -- vault operator unseal <KEY-3>

# Unseal vault-2
kubectl -n vault exec -it vault-2 -- vault operator unseal <KEY-1>
kubectl -n vault exec -it vault-2 -- vault operator unseal <KEY-2>
kubectl -n vault exec -it vault-2 -- vault operator unseal <KEY-3>
```

Verify all three nodes are ready and part of the Raft cluster:

```bash
kubectl -n vault get pods
kubectl -n vault exec -it vault-0 -- vault login <ROOT-TOKEN>
kubectl -n vault exec -it vault-0 -- vault operator raft list-peers
```

You should see all three nodes listed as Raft peers.

## 8. Verify Enterprise License

Login to Vault with the root token:

```bash
kubectl -n vault exec -it vault-0 -- vault login <ROOT-TOKEN>
```

Check that Enterprise mode is active:

```bash
kubectl -n vault exec -it vault-0 -- vault read sys/health
```

Look for:
- `"enterprise": true`
- `"version": "1.20.4+ent"` (note the `+ent` suffix)
- `"license": map[...state:autoloaded...]`

## 9. Optional Next Steps

- **Expose the UI:** Set `server.service.type=LoadBalancer` in a values override or configure an Ingress.
- **Enable TLS:** Replace the `tls_disable = "true"` listener in `helm-vault-raft-values.yml` with proper certificates before production use.
- **Enable Auto-Unseal:** Integrate with AWS KMS or an HSM to avoid manual unseal operations after restarts.
- **Configure Auth & Secrets Engines:** Use the root token to set up auth methods (e.g., AWS IAM, Kubernetes) and your required secrets engines.
- **Enable Audit Logging:** Direct audit logs to CloudWatch, S3, or another compliant destination.

## Troubleshooting Tips

- Check pod logs: `kubectl -n vault logs statefulset/vault`
- Describe pods/services: `kubectl -n vault describe pod vault-0`
- Confirm PVCs are bound (Raft storage needs persistent volumes): `kubectl -n vault get pvc`
