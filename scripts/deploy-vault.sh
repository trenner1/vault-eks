#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="vault"
RELEASE_NAME="vault"
HELM_CHART="hashicorp/vault"
VAULT_LICENSE_FILE="vault.hclic"

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo ""
    echo -e "${GREEN}================================${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${GREEN}================================${NC}"
    echo ""
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    local missing_tools=()
    
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi
    
    if ! command -v helm &> /dev/null; then
        missing_tools+=("helm")
    fi
    
    if ! command -v aws &> /dev/null; then
        missing_tools+=("aws")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
    
    print_success "All required tools installed"
    
    # Check kubectl connectivity
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    print_success "Connected to Kubernetes cluster"
    
    # Check for license file
    if [ ! -f "$VAULT_LICENSE_FILE" ]; then
        print_error "License file not found: $VAULT_LICENSE_FILE"
        print_info "Please place your Vault Enterprise license in $VAULT_LICENSE_FILE"
        exit 1
    fi
    
    print_success "License file found"
}

# Add Helm repository
add_helm_repo() {
    print_header "Adding Helm Repository"
    
    helm repo add hashicorp https://helm.releases.hashicorp.com
    helm repo update
    
    print_success "Helm repository updated"
}

# Create namespace
create_namespace() {
    print_header "Creating Namespace"
    
    if kubectl get namespace $NAMESPACE &> /dev/null; then
        print_warning "Namespace $NAMESPACE already exists"
    else
        kubectl create namespace $NAMESPACE
        print_success "Namespace $NAMESPACE created"
    fi
}

# Create license secret
create_license_secret() {
    print_header "Creating License Secret"
    
    local license=$(cat $VAULT_LICENSE_FILE)
    
    if kubectl -n $NAMESPACE get secret vault-ent-license &> /dev/null; then
        print_warning "License secret already exists, deleting..."
        kubectl -n $NAMESPACE delete secret vault-ent-license
    fi
    
    kubectl -n $NAMESPACE create secret generic vault-ent-license \
        --from-literal="license=${license}"
    
    print_success "License secret created"
}

# Deploy Vault
deploy_vault() {
    print_header "Deploying Vault Enterprise"
    
    if helm list -n $NAMESPACE | grep -q $RELEASE_NAME; then
        print_warning "Vault release already exists, upgrading..."
        helm upgrade $RELEASE_NAME $HELM_CHART \
            --namespace $NAMESPACE \
            -f config/config.yml \
            -f config/helm-vault-raft-values.yml
    else
        helm install $RELEASE_NAME $HELM_CHART \
            --namespace $NAMESPACE \
            -f config/config.yml \
            -f config/helm-vault-raft-values.yml
    fi
    
    print_success "Vault deployed"
}

# Wait for pods
wait_for_pods() {
    print_header "Waiting for Vault Pods"
    
    print_info "Waiting for vault-0 to be ready..."
    kubectl -n $NAMESPACE wait --for=condition=Ready pod/vault-0 --timeout=300s
    
    print_info "Waiting for vault-1 to be running..."
    kubectl -n $NAMESPACE wait --for=condition=PodScheduled pod/vault-1 --timeout=300s
    
    print_info "Waiting for vault-2 to be running..."
    kubectl -n $NAMESPACE wait --for=condition=PodScheduled pod/vault-2 --timeout=300s
    
    print_success "All Vault pods are ready"
}

# Initialize Vault
initialize_vault() {
    print_header "Initializing Vault"
    
    # Check if already initialized
    if kubectl -n $NAMESPACE exec vault-0 -- vault status &> /dev/null; then
        print_warning "Vault is already initialized"
        return 0
    fi
    
    print_info "Initializing Vault with 5 key shares and threshold of 3..."
    
    kubectl -n $NAMESPACE exec vault-0 -- vault operator init \
        -key-shares=5 \
        -key-threshold=3 \
        -format=json > vault-init.json
    
    print_success "Vault initialized"
    print_warning "Unseal keys and root token saved to vault-init.json"
    print_warning "IMPORTANT: Store these keys securely and delete vault-init.json!"
    
    # Extract keys for unsealing
    export VAULT_UNSEAL_KEY_1=$(cat vault-init.json | jq -r '.unseal_keys_b64[0]')
    export VAULT_UNSEAL_KEY_2=$(cat vault-init.json | jq -r '.unseal_keys_b64[1]')
    export VAULT_UNSEAL_KEY_3=$(cat vault-init.json | jq -r '.unseal_keys_b64[2]')
    export VAULT_ROOT_TOKEN=$(cat vault-init.json | jq -r '.root_token')
}

# Unseal Vault nodes
unseal_vault() {
    print_header "Unsealing Vault Nodes"
    
    if [ -z "$VAULT_UNSEAL_KEY_1" ]; then
        if [ -f "vault-init.json" ]; then
            export VAULT_UNSEAL_KEY_1=$(cat vault-init.json | jq -r '.unseal_keys_b64[0]')
            export VAULT_UNSEAL_KEY_2=$(cat vault-init.json | jq -r '.unseal_keys_b64[1]')
            export VAULT_UNSEAL_KEY_3=$(cat vault-init.json | jq -r '.unseal_keys_b64[2]')
            export VAULT_ROOT_TOKEN=$(cat vault-init.json | jq -r '.root_token')
        else
            print_error "Unseal keys not found. Please provide them manually."
            print_info "Run: kubectl -n $NAMESPACE exec -it vault-0 -- vault operator unseal"
            return 1
        fi
    fi
    
    for pod in vault-0 vault-1 vault-2; do
        print_info "Unsealing $pod..."
        kubectl -n $NAMESPACE exec $pod -- vault operator unseal $VAULT_UNSEAL_KEY_1 > /dev/null
        kubectl -n $NAMESPACE exec $pod -- vault operator unseal $VAULT_UNSEAL_KEY_2 > /dev/null
        kubectl -n $NAMESPACE exec $pod -- vault operator unseal $VAULT_UNSEAL_KEY_3 > /dev/null
        print_success "$pod unsealed"
    done
}

# Join Raft cluster
join_raft_cluster() {
    print_header "Joining Raft Cluster"
    
    # vault-0 is already the leader, join vault-1 and vault-2
    print_info "Joining vault-1 to cluster..."
    kubectl -n $NAMESPACE exec vault-1 -- vault operator raft join http://vault-0.vault-internal:8200 || print_warning "vault-1 may already be joined"
    
    print_info "Joining vault-2 to cluster..."
    kubectl -n $NAMESPACE exec vault-2 -- vault operator raft join http://vault-0.vault-internal:8200 || print_warning "vault-2 may already be joined"
    
    print_success "Raft cluster joined"
}

# Verify cluster status
verify_cluster() {
    print_header "Verifying Cluster Status"
    
    if [ -z "$VAULT_ROOT_TOKEN" ]; then
        if [ -f "vault-init.json" ]; then
            export VAULT_ROOT_TOKEN=$(cat vault-init.json | jq -r '.root_token')
        else
            print_warning "Root token not available, skipping verification"
            return 0
        fi
    fi
    
    print_info "Cluster peers:"
    kubectl -n $NAMESPACE exec vault-0 -- sh -c "VAULT_TOKEN=$VAULT_ROOT_TOKEN vault operator raft list-peers"
    
    echo ""
    print_info "Vault status:"
    kubectl -n $NAMESPACE exec vault-0 -- vault status
    
    echo ""
    print_success "Vault cluster is operational!"
}

# Enable audit logging
enable_audit_logging() {
    print_header "Enabling Audit Logging"
    
    if [ -z "$VAULT_ROOT_TOKEN" ]; then
        print_warning "Root token not available, skipping audit device setup"
        print_info "To enable manually: kubectl -n $NAMESPACE exec -it vault-0 -- sh -c 'VAULT_TOKEN=<root-token> vault audit enable file file_path=stdout'"
        return 0
    fi
    
    print_info "Enabling stdout audit device..."
    kubectl -n $NAMESPACE exec vault-0 -- sh -c "VAULT_TOKEN=$VAULT_ROOT_TOKEN vault audit enable file file_path=stdout" 2>/dev/null || print_warning "Audit device may already be enabled"
    
    print_success "Audit logging enabled"
}

# Setup port forwarding
setup_port_forward() {
    print_header "Port Forwarding Information"
    
    print_info "To access Vault UI locally, run:"
    echo ""
    echo "  kubectl -n $NAMESPACE port-forward vault-0 8200:8200"
    echo ""
    print_info "Then access Vault at: http://localhost:8200/ui"
    
    if [ -n "$VAULT_ROOT_TOKEN" ]; then
        echo ""
        print_info "Root Token: $VAULT_ROOT_TOKEN"
    fi
}

# Cleanup sensitive files
cleanup() {
    print_header "Cleanup"
    
    if [ -f "vault-init.json" ]; then
        print_warning "vault-init.json contains sensitive data!"
        print_info "Please save the unseal keys and root token securely, then delete this file."
        echo ""
        read -p "Delete vault-init.json now? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm vault-init.json
            print_success "vault-init.json deleted"
        fi
    fi
}

# Main deployment flow
main() {
    print_header "Vault Enterprise Deployment on EKS"
    
    check_prerequisites
    add_helm_repo
    create_namespace
    create_license_secret
    deploy_vault
    wait_for_pods
    initialize_vault
    unseal_vault
    join_raft_cluster
    verify_cluster
    enable_audit_logging
    setup_port_forward
    cleanup
    
    print_header "Deployment Complete!"
    print_success "Vault Enterprise is ready to use"
    
    echo ""
    print_info "Next steps:"
    echo "  1. Save your unseal keys and root token securely"
    echo "  2. Run CloudWatch logging setup: ./setup-cloudwatch-logging.sh"
    echo "  3. Configure authentication methods"
    echo "  4. Set up secrets engines"
    echo ""
}

# Run main function
main "$@"
