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
    echo -e "${RED}================================${NC}"
    echo -e "${RED}$1${NC}"
    echo -e "${RED}================================${NC}"
    echo ""
}

# Confirm deletion
confirm_deletion() {
    print_header "Vault Enterprise Teardown"
    
    print_warning "This will DELETE the following resources:"
    echo "  - Vault Helm release: $RELEASE_NAME"
    echo "  - Namespace: $NAMESPACE (including all PVCs and data)"
    echo "  - All Vault data will be PERMANENTLY LOST"
    echo ""
    
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " -r
    echo
    
    if [[ ! $REPLY == "yes" ]]; then
        print_info "Teardown cancelled"
        exit 0
    fi
}

# Delete Helm release
delete_helm_release() {
    print_header "Deleting Helm Release"
    
    if helm list -n $NAMESPACE | grep -q $RELEASE_NAME; then
        helm uninstall $RELEASE_NAME -n $NAMESPACE
        print_success "Helm release deleted"
    else
        print_warning "Helm release not found"
    fi
}

# Delete Fluent Bit (if installed)
delete_fluent_bit() {
    print_header "Deleting Fluent Bit"
    
    if kubectl -n $NAMESPACE get daemonset fluent-bit &> /dev/null; then
        kubectl -n $NAMESPACE delete daemonset fluent-bit
        kubectl -n $NAMESPACE delete configmap fluent-bit-config
        kubectl -n $NAMESPACE delete serviceaccount fluent-bit
        kubectl delete clusterrole fluent-bit-read
        kubectl delete clusterrolebinding fluent-bit-read
        print_success "Fluent Bit deleted"
    else
        print_warning "Fluent Bit not found"
    fi
}

# Delete PVCs
delete_pvcs() {
    print_header "Deleting Persistent Volume Claims"
    
    local pvcs=$(kubectl -n $NAMESPACE get pvc -o name 2>/dev/null)
    
    if [ -n "$pvcs" ]; then
        print_warning "Deleting PVCs (this will delete all Vault data):"
        echo "$pvcs"
        kubectl -n $NAMESPACE delete pvc --all
        print_success "PVCs deleted"
    else
        print_warning "No PVCs found"
    fi
}

# Delete namespace
delete_namespace() {
    print_header "Deleting Namespace"
    
    if kubectl get namespace $NAMESPACE &> /dev/null; then
        kubectl delete namespace $NAMESPACE
        print_success "Namespace deleted"
    else
        print_warning "Namespace not found"
    fi
}

# Delete local files
delete_local_files() {
    print_header "Cleaning Local Files"
    
    local files_to_delete=(
        "vault-init.json"
        "trust-policy.json"
        "fluent-bit-config-temp.yaml"
        "fluent-bit-daemonset-temp.yaml"
    )
    
    for file in "${files_to_delete[@]}"; do
        if [ -f "$file" ]; then
            rm "$file"
            print_success "Deleted $file"
        fi
    done
}

# Optional: Delete IAM resources
delete_iam_resources() {
    print_header "IAM Resources Cleanup (Optional)"
    
    print_info "The following IAM resources may have been created:"
    echo "  - IAM Policy: VaultCloudWatchLogsPolicy"
    echo "  - IAM Role: VaultFluentBitRole"
    echo ""
    
    read -p "Delete IAM resources? (y/N) " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Get AWS account ID
        AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
        
        if [ -n "$AWS_ACCOUNT_ID" ]; then
            # Detach and delete policy
            POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/VaultCloudWatchLogsPolicy"
            
            if aws iam get-policy --policy-arn "$POLICY_ARN" &> /dev/null; then
                aws iam detach-role-policy --role-name VaultFluentBitRole --policy-arn "$POLICY_ARN" 2>/dev/null || true
                aws iam delete-policy --policy-arn "$POLICY_ARN" 2>/dev/null || true
                print_success "Deleted IAM policy"
            fi
            
            # Delete role
            if aws iam get-role --role-name VaultFluentBitRole &> /dev/null; then
                aws iam delete-role --role-name VaultFluentBitRole 2>/dev/null || true
                print_success "Deleted IAM role"
            fi
        fi
    else
        print_info "Skipping IAM cleanup"
    fi
}

# Main teardown flow
main() {
    confirm_deletion
    delete_helm_release
    delete_fluent_bit
    delete_pvcs
    delete_namespace
    delete_local_files
    delete_iam_resources
    
    print_header "Teardown Complete!"
    print_success "All Vault resources have been removed"
    
    echo ""
    print_warning "Note: CloudWatch log groups may still exist"
    print_info "To delete logs: aws logs delete-log-group --log-group-name /aws/eks/vault/audit"
    echo ""
}

# Run main function
main "$@"
