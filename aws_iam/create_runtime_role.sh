set -euo pipefail

ACCOUNT_ID="${ACCOUNT_ID:-}"

: "${ACCOUNT_ID:?Must set ACCOUNT_ID}"

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
  --role-name kube-montecarlo-jobs-runtime \
  --assume-role-policy-document file://trust-policy.json

cat <<EOF > ec2-runtime-sqs-ddb-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "DescribeEc2ForIpLookup",
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances",
                "ec2:DescribeTags"
            ],
            "Resource": "*"
        },
        {
            "Sid": "EcrAuthForImagePullSecret",
            "Effect": "Allow",
            "Action": "ecr:GetAuthorizationToken",
            "Resource": "*"
        },
        {
            "Sid": "CallerIdentity",
            "Effect": "Allow",
            "Action": "sts:GetCallerIdentity",
            "Resource": "*"
        },
        {
            "Sid": "GetQueueUrl",
            "Effect": "Allow",
            "Action": "sqs:GetQueueUrl",
            "Resource": "*"
        },
        {
            "Sid": "EcrPullRead",
            "Effect": "Allow",
            "Action": [
                "ecr:BatchGetImage",
                "ecr:BatchCheckLayerAvailability",
                "ecr:GetDownloadUrlForLayer"
            ],
            "Resource": "arn:aws:ecr:us-west-2:611754262869:repository/kube-montecarlo-jobs-*"
        }
    ]
}
EOF

aws iam create-policy \
  --policy-name "kube-montecarlo-jobs-runtime-sqs-ddb" \
  --policy-document file://ec2-runtime-sqs-ddb-policy.json

aws iam attach-role-policy \
  --role-name "kube-montecarlo-jobs-runtime" \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/kube-montecarlo-jobs-runtime-sqs-ddb"
