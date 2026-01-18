set -euo pipefail

ACCOUNT_ID="${ACCOUNT_ID:-}"

: "${ACCOUNT_ID:?Must set ACCOUNT_ID}"

# Create an EC2 role + instance profile

aws iam create-instance-profile \
  --instance-profile-name "kube-montecarlo-jobs-ec2"

cat <<EOF > ec2-trust.json 
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
  --role-name "kube-montecarlo-jobs-ec2" \
  --assume-role-policy-document file://ec2-trust.json

aws iam add-role-to-instance-profile \
  --instance-profile-name "kube-montecarlo-jobs-ec2" \
  --role-name "kube-montecarlo-jobs-ec2"

# Create policy and add it to EC2 role

cat <<EOF > runtime-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "SqsAccessJobsQueue",
      "Effect": "Allow",
      "Action": [
        "sqs:GetQueueAttributes",
        "sqs:SendMessage",
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:ChangeMessageVisibility"
      ],
      "Resource": "arn:aws:sqs:us-west-2:611754262869:kube-montecarlo-jobs-queue"
    },
    {
      "Sid": "DynamoRwJobsTable",
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Scan",
        "dynamodb:Query"
      ],
      "Resource": [
        "arn:aws:dynamodb:us-west-2:611754262869:table/kube-montecarlo-jobs-results",
        "arn:aws:dynamodb:us-west-2:611754262869:table/kube-montecarlo-jobs-results/index/*"
      ]
    },
    {
      "Sid": "EcrAuthForImagePullSecret",
      "Effect": "Allow",
      "Action": "ecr:GetAuthorizationToken",
      "Resource": "*"
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name "kube-montecarlo-jobs-ec2-runtime" \
  --policy-document file://runtime-policy.json

aws iam attach-role-policy \
  --role-name "kube-montecarlo-jobs-ec2" \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/kube-montecarlo-jobs-ec2-runtime"
