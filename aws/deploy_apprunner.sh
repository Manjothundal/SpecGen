#!/usr/bin/env bash
# Build the Docker image, push it to ECR, and create (or update) an AWS App
# Runner service running it. NOT run automatically by anything — a human
# reviews and runs this deliberately, with AWS credentials already
# configured (aws configure / SSO) and the AWS CLI installed.
#
# Usage:
#   ANTHROPIC_API_KEY=sk-... ./aws/deploy_apprunner.sh [aws-region] [service-name]
#
# Cost note: App Runner bills per vCPU/memory-second while the service is
# provisioned, roughly a few $/month for the smallest instance size (1
# vCPU / 2GB) at low traffic, scaling with usage — check current pricing
# before deploying. Nothing here provisions or spends anything until you
# actually run it.
set -euo pipefail

REGION="${1:-us-east-1}"
SERVICE_NAME="${2:-specgen}"
REPO_NAME="specgen"

if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "ANTHROPIC_API_KEY is not set — API/Hybrid mode won't work without it." >&2
  echo "Set it and re-run, or continue if you only need local/mock mode." >&2
  read -rp "Continue without it? [y/N] " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]] || exit 1
fi

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}"

echo "== Ensuring ECR repo exists =="
aws ecr describe-repositories --repository-names "$REPO_NAME" --region "$REGION" \
  >/dev/null 2>&1 || aws ecr create-repository --repository-name "$REPO_NAME" --region "$REGION"

echo "== Building image =="
docker build -t "$REPO_NAME:latest" ..

echo "== Pushing to ECR =="
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
docker tag "$REPO_NAME:latest" "${ECR_URI}:latest"
docker push "${ECR_URI}:latest"

echo "== Creating/updating App Runner service =="
SERVICE_ARN="$(aws apprunner list-services --region "$REGION" \
  --query "ServiceSummaryList[?ServiceName=='${SERVICE_NAME}'].ServiceArn" --output text)"

# App Runner needs an IAM role that can pull from ECR — see
# aws/apprunner-ecr-access-role-trust-policy.json for the trust policy if
# you need to create ACCESS_ROLE_ARN from scratch.
ACCESS_ROLE_ARN="${APPRUNNER_ECR_ACCESS_ROLE_ARN:?Set APPRUNNER_ECR_ACCESS_ROLE_ARN to an IAM role App Runner can assume to pull from ECR (see aws/README.md)}"

SOURCE_CONFIG=$(cat <<JSON
{
  "ImageRepository": {
    "ImageIdentifier": "${ECR_URI}:latest",
    "ImageRepositoryType": "ECR",
    "ImageConfiguration": {
      "Port": "5000",
      "RuntimeEnvironmentVariables": {
        "ANTHROPIC_API_KEY": "${ANTHROPIC_API_KEY:-}"
      }
    }
  },
  "AuthenticationConfiguration": { "AccessRoleArn": "${ACCESS_ROLE_ARN}" },
  "AutoDeploymentsEnabled": false
}
JSON
)

if [[ -n "$SERVICE_ARN" && "$SERVICE_ARN" != "None" ]]; then
  aws apprunner update-service --region "$REGION" --service-arn "$SERVICE_ARN" \
    --source-configuration "$SOURCE_CONFIG"
else
  aws apprunner create-service --region "$REGION" --service-name "$SERVICE_NAME" \
    --source-configuration "$SOURCE_CONFIG" \
    --instance-configuration '{"Cpu":"1 vCPU","Memory":"2 GB"}'
fi

echo "== Done. Check status with: =="
echo "aws apprunner describe-service --region $REGION --service-arn <arn> --query Service.Status"
