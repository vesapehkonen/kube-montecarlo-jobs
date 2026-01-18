set -euo pipefail

ACCOUNT_ID="${ACCOUNT_ID:-}"
GITHUB_USERNAME="${GITHUB_USERNAME:-}"
REGION=us-west-2

: "${ACCOUNT_ID:?Must set ACCOUNT_ID}"
: "${GITHUB_USERNAME:?Must set GITHUB_USERNAME}"

cat <<EOF > trust-policy.json 
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:${GITHUB_USERNAME}/kube-montecarlo-jobs:*"
        }
      }
    }
  ]
}
EOF

# Create role

aws iam create-role \
  --role-name kube-montecarlo-jobs-ecr \
  --assume-role-policy-document file://trust-policy.json

cat <<EOF > ecr-push-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EcrAuth",
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EcrPushPullSpecificRepos",
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:CompleteLayerUpload",
        "ecr:GetDownloadUrlForLayer",
        "ecr:InitiateLayerUpload",
        "ecr:PutImage",
        "ecr:UploadLayerPart",
        "ecr:DescribeRepositories",
        "ecr:ListImages"
      ],
      "Resource": [
        "arn:aws:ecr:${REGION}:${ACCOUNT_ID}:repository/kube-montecarlo-jobs-api",
        "arn:aws:ecr:${REGION}:${ACCOUNT_ID}:repository/kube-montecarlo-jobs-worker"
      ]
    }
  ]
}
EOF

# Create policy

aws iam create-policy \
  --policy-name kube-montecarlo-jobs-ecr-push \
  --policy-document file://ecr-push-policy.json

# Attach policy to role

aws iam attach-role-policy \
  --role-name kube-montecarlo-jobs-ecr \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/kube-montecarlo-jobs-ecr-push



