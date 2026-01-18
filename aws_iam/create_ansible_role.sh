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
  --role-name kube-montecarlo-jobs-ansible \
  --assume-role-policy-document file://trust-policy.json


cat <<EOF > ansible-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DescribeInstances",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeTags"
      ],
      "Resource": "*"
    }
  ]
}
EOF


# Create the policies and attach the policy to the role:

aws iam create-policy \
  --policy-name "kube-montecarlo-jobs-install-kube" \
  --policy-document "file://ansible-policy.json"
  
aws iam attach-role-policy \
  --role-name "kube-montecarlo-jobs-ansible" \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/kube-montecarlo-jobs-install-kube"


