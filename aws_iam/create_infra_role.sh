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
  --role-name kube-montecarlo-jobs-infra \
  --assume-role-policy-document file://trust-policy.json


cat <<EOF > tf-ec2-network-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "ReadForDataSourcesAndStateRefresh",
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeAvailabilityZones",
                "ec2:DescribeInstanceAttribute",
                "ec2:DescribeImages",
                "ec2:DescribeInstanceTypes",
                "ec2:DescribeInstances",
                "ec2:DescribeInstanceStatus",
                "ec2:DescribeVpcs",
                "ec2:DescribeVpcAttribute",
                "ec2:DescribeSubnets",
                "ec2:DescribeRouteTables",
                "ec2:DescribeInternetGateways",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeAccountAttributes",
                "ec2:DescribeVpcClassicLink",
                "ec2:DescribeTags",
                "ec2:DescribeNetworkInterfaces",
                "ec2:DescribeAddresses",
                "ec2:DescribeKeyPairs",
                "ec2:DescribeVolumes",
                "ec2:DescribeVolumeAttribute",
                "ec2:DescribeSnapshots",
                "ec2:DescribeInstanceCreditSpecifications",
                "ec2:DescribeIamInstanceProfileAssociations",
                "ec2:DescribeSecurityGroupRules",
                "ec2:DescribeLaunchTemplates"
            ],
            "Resource": "*"
        },
        {
            "Sid": "ManageVpcAndNetworking",
            "Effect": "Allow",
            "Action": [
                "ec2:CreateVpc",
                "ec2:DeleteVpc",
                "ec2:ModifyVpcAttribute",
                "ec2:CreateSubnet",
                "ec2:DeleteSubnet",
                "ec2:ModifySubnetAttribute",
                "ec2:CreateInternetGateway",
                "ec2:DeleteInternetGateway",
                "ec2:AttachInternetGateway",
                "ec2:DetachInternetGateway",
                "ec2:CreateRouteTable",
                "ec2:DeleteRouteTable",
                "ec2:AssociateRouteTable",
                "ec2:DisassociateRouteTable",
                "ec2:CreateRoute",
                "ec2:DeleteRoute",
                "ec2:CreateSecurityGroup",
                "ec2:DeleteSecurityGroup",
                "ec2:AuthorizeSecurityGroupIngress",
                "ec2:RevokeSecurityGroupIngress",
                "ec2:AuthorizeSecurityGroupEgress",
                "ec2:RevokeSecurityGroupEgress",
                "ec2:CreateTags",
                "ec2:DeleteTags"
            ],
            "Resource": "*"
        },
        {
            "Sid": "ManageEc2Instance",
            "Effect": "Allow",
            "Action": [
                "ec2:RunInstances",
                "ec2:TerminateInstances"
            ],
            "Resource": "*"
        }
    ]
}
EOF

cat <<EOF > tf-passrole-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowPassEc2InstanceRoleOnlyToEc2",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::${ACCOUNT_ID}:role/kube-montecarlo-jobs-ec2",
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": "ec2.amazonaws.com"
        }
      }
    }
  ]
}
EOF

# Create the policies and attach the policy to the role:

aws iam create-policy \
  --policy-name "kube-montecarlo-jobs-ec2-network" \
  --policy-document "file://tf-ec2-network-policy.json"
  
aws iam attach-role-policy \
  --role-name "kube-montecarlo-jobs-infra" \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/kube-montecarlo-jobs-ec2-network"

aws iam create-policy \
  --policy-name "kube-montecarlo-jobs-ec2-passrole" \
  --policy-document file://tf-passrole-policy.json

aws iam attach-role-policy \
  --role-name "kube-montecarlo-jobs-infra" \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/kube-montecarlo-jobs-ec2-passrole"

cat <<EOF > tf-sqs-ddb-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "SQSManageForTerraform",
            "Effect": "Allow",
            "Action": [
                "sqs:CreateQueue",
                "sqs:DeleteQueue",
                "sqs:GetQueueAttributes",
                "sqs:SetQueueAttributes",
                "sqs:GetQueueUrl",
                "sqs:ListQueueTags",
                "sqs:TagQueue",
                "sqs:UntagQueue"
            ],
            "Resource": "*"
        },
        {
            "Sid": "DynamoDBManageForTerraform",
            "Effect": "Allow",
            "Action": [
                "dynamodb:CreateTable",
                "dynamodb:DeleteTable",
                "dynamodb:DescribeTable",
                "dynamodb:UpdateTable",
                "dynamodb:ListTagsOfResource",
                "dynamodb:TagResource",
                "dynamodb:UntagResource",
                "dynamodb:DescribeContinuousBackups",
                "dynamodb:DescribeTimeToLive",
                "dynamodb:DescribeContributorInsights"
            ],
            "Resource": "*"
        }
    ]
}
EOF

# Create policy for DynamoDB and SQS

aws iam create-policy \
  --policy-name "kube-montecarlo-jobs-sqs-ddb" \
  --policy-document file://tf-sqs-ddb-policy.json

aws iam attach-role-policy \
  --role-name "kube-montecarlo-jobs-infra" \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/kube-montecarlo-jobs-sqs-ddb"


cat <<EOF > tf-state-s3-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "ListBucketForState",
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket",
                "s3:GetBucketLocation"
            ],
            "Resource": "arn:aws:s3:::kube-montecarlo-jobs"
        },
        {
            "Sid": "ObjectAccessForState",
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject"
            ],
            "Resource": "arn:aws:s3:::kube-montecarlo-jobs/terraform/*"
        }
    ]
}
EOF


aws iam create-policy \
  --policy-name "kube-montecarlo-jobs-s3" \
  --policy-document file://tf-state-s3-policy.json

aws iam attach-role-policy \
  --role-name "kube-montecarlo-jobs-infra" \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/kube-montecarlo-jobs-s3"
