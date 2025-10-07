#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Setting up CloudWatch Logs for Vault Audit${NC}"

# Check prerequisites
if ! command -v aws &> /dev/null; then
    echo "AWS CLI not found. Please install it first."
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo "kubectl not found. Please install it first."
    exit 1
fi

# Get AWS account ID and region
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=${AWS_REGION:-$(aws configure get region)}

echo -e "${GREEN}AWS Account ID: ${AWS_ACCOUNT_ID}${NC}"
echo -e "${GREEN}AWS Region: ${AWS_REGION}${NC}"

# Get EKS cluster name
read -p "Enter your EKS cluster name: " EKS_CLUSTER_NAME

# Get OIDC provider
OIDC_PROVIDER=$(aws eks describe-cluster --name $EKS_CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text | sed -e "s/^https:\/\///")
echo -e "${GREEN}OIDC Provider: ${OIDC_PROVIDER}${NC}"

# Create IAM policy
POLICY_NAME="VaultCloudWatchLogsPolicy"
echo -e "${YELLOW}Creating IAM policy: ${POLICY_NAME}${NC}"

POLICY_ARN=$(aws iam create-policy \
    --policy-name $POLICY_NAME \
    --policy-document file://config/cloudwatch/cloudwatch-policy.json \
    --query 'Policy.Arn' \
    --output text 2>/dev/null || aws iam list-policies --query "Policies[?PolicyName=='${POLICY_NAME}'].Arn" --output text)

echo -e "${GREEN}Policy ARN: ${POLICY_ARN}${NC}"

# Create trust policy for IRSA
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:vault:fluent-bit",
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF

# Create IAM role for Fluent Bit
ROLE_NAME="VaultFluentBitRole"
echo -e "${YELLOW}Creating IAM role: ${ROLE_NAME}${NC}"

ROLE_ARN=$(aws iam create-role \
    --role-name $ROLE_NAME \
    --assume-role-policy-document file://trust-policy.json \
    --query 'Role.Arn' \
    --output text 2>/dev/null || aws iam get-role --role-name $ROLE_NAME --query 'Role.Arn' --output text)

echo -e "${GREEN}Role ARN: ${ROLE_ARN}${NC}"

# Attach policy to role
echo -e "${YELLOW}Attaching policy to role${NC}"
aws iam attach-role-policy \
    --role-name $ROLE_NAME \
    --policy-arn $POLICY_ARN 2>/dev/null || echo "Policy already attached"

# Update Fluent Bit manifests with actual values
echo -e "${YELLOW}Updating Fluent Bit manifests${NC}"
sed "s|\${FLUENT_BIT_IAM_ROLE_ARN}|${ROLE_ARN}|g" config/fluent-bit/fluent-bit-daemonset.yaml > fluent-bit-daemonset-temp.yaml
sed -i.bak "s|\${AWS_REGION}|${AWS_REGION}|g" fluent-bit-daemonset-temp.yaml
rm -f fluent-bit-daemonset-temp.yaml.bak

sed "s|\${AWS_REGION}|${AWS_REGION}|g" config/fluent-bit/fluent-bit-config.yaml > fluent-bit-config-temp.yaml

# Apply Kubernetes resources
echo -e "${YELLOW}Applying Fluent Bit configuration${NC}"
kubectl apply -f fluent-bit-config-temp.yaml
kubectl apply -f fluent-bit-daemonset-temp.yaml

# Wait for Fluent Bit to be ready
echo -e "${YELLOW}Waiting for Fluent Bit pods to be ready${NC}"
kubectl -n vault rollout status daemonset/fluent-bit --timeout=120s

# Enable Vault audit device to stdout
echo -e "${YELLOW}Enabling Vault audit device (stdout)${NC}"
echo "Please enable the audit device manually with your Vault token:"
echo "  kubectl -n vault exec -it vault-0 -- sh -c 'VAULT_TOKEN=<your-root-token> vault audit enable file file_path=stdout'"

# Clean up temp files
rm -f trust-policy.json fluent-bit-config-temp.yaml fluent-bit-daemonset-temp.yaml

echo -e "${GREEN}✓ CloudWatch logging setup complete!${NC}"
echo ""
echo "Logs will be available in CloudWatch Logs at:"
echo "  Log Group: /aws/eks/vault/audit"
echo "  Region: ${AWS_REGION}"
echo ""
echo "To view logs:"
echo "  aws logs tail /aws/eks/vault/audit --follow --region ${AWS_REGION}"
