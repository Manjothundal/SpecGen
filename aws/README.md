# Deploying SpecGen to AWS

Two options, both starting from the same `Dockerfile` at the repo root.
Neither is run automatically by anything in this repo — review the script
before running it, with the AWS CLI installed and credentials configured
(`aws configure` or SSO) for an account you're willing to spend on.

## Option A: App Runner (recommended — fully managed, HTTPS built in)

```
export ANTHROPIC_API_KEY=sk-...
export APPRUNNER_ECR_ACCESS_ROLE_ARN=arn:aws:iam::<account>:role/AppRunnerECRAccessRole
./aws/deploy_apprunner.sh us-east-1 specgen
```

`APPRUNNER_ECR_ACCESS_ROLE_ARN` is an IAM role App Runner assumes to pull
from ECR — create it once with the trust policy in
`aws/apprunner-ecr-access-role-trust-policy.json` and the AWS-managed
`AWSAppRunnerServicePolicyForECRAccess` policy attached:

```
aws iam create-role --role-name AppRunnerECRAccessRole \
  --assume-role-policy-document file://aws/apprunner-ecr-access-role-trust-policy.json
aws iam attach-role-policy --role-name AppRunnerECRAccessRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess
```

The script builds the image, pushes it to ECR, and creates (or updates) the
App Runner service. App Runner assigns a public HTTPS URL automatically.

Cost: billed per vCPU/memory-second while provisioned — roughly a few
$/month at the smallest size (1 vCPU / 2GB) and low traffic; check current
App Runner pricing before deploying.

## Option B: EC2 (cheaper at idle, more to manage yourself)

1. Push the image to ECR first (the first three steps of
   `deploy_apprunner.sh`, or just run that script — it's harmless to also
   have an App Runner service you don't use, but you can stop after the
   push step if you only want EC2).
2. Launch a `t3.micro` or `t3.small` with the Amazon Linux 2023 AMI, an
   instance profile that can pull from ECR, and security group inbound
   rules for 80/tcp (and 443/tcp if you put a load balancer or your own
   TLS in front of it — this setup is plain HTTP on port 80).
3. Paste `aws/ec2_user_data.sh` into "User data" at launch, after filling
   in `ECR_IMAGE_URI` and `ANTHROPIC_API_KEY_VALUE` (or better, swap the
   hardcoded key for an SSM Parameter Store / Secrets Manager read — see
   the comment in that file).

Cost: a `t3.micro` is free-tier eligible for 12 months on a new AWS
account (check current terms); afterward, low single-digit $/month.

## Either way

- `ANTHROPIC_API_KEY` is the only required secret — API mode works out of
  the box once it's set. Offline/Hybrid mode's local Writer needs an
  Ollama instance reachable from wherever the container runs (not
  included here — this containerizes the Flask app, not a full Ollama
  stack); set `OLLAMA_HOST` and adjust `generator.py`'s local endpoint if
  you want that too.
- State (`RUN_STATE` in app.py) is a single in-memory dict, by design (see
  ROADMAP.md) — this is a single-operator tool. Don't scale App Runner
  past 1 concurrent instance, or run more than one EC2 instance behind a
  load balancer, without adding a real session/state layer first.
