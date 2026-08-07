#!/usr/bin/env bash
# EC2 user-data script (Amazon Linux 2023) — the alternative to App Runner.
# Paste this into the instance's "User data" field at launch (a t3.micro/
# t3.small is plenty for a single-operator tool; t3.micro is free-tier
# eligible for 12 months on a new account — check current AWS free-tier
# terms before relying on that).
#
# Fill in the two placeholders below before launch. For anything beyond a
# personal/demo deployment, pull ANTHROPIC_API_KEY from SSM Parameter Store
# or Secrets Manager instead of hardcoding it into user-data (user-data is
# visible to anyone with DescribeInstanceAttribute on the instance).

set -euxo pipefail

ECR_IMAGE_URI="REPLACE_ME.dkr.ecr.REPLACE_REGION.amazonaws.com/specgen:latest"
ANTHROPIC_API_KEY_VALUE="REPLACE_ME"

dnf install -y docker
systemctl enable --now docker

aws ecr get-login-password --region "$(echo "$ECR_IMAGE_URI" | cut -d. -f4)" \
  | docker login --username AWS --password-stdin "$(echo "$ECR_IMAGE_URI" | cut -d/ -f1)"

docker pull "$ECR_IMAGE_URI"
docker run -d --name specgen --restart unless-stopped \
  -p 80:5000 \
  -e ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY_VALUE" \
  "$ECR_IMAGE_URI"
