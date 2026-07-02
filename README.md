# AI Auto-Healing on AWS

An intelligent auto-healing system that detects application errors via CloudWatch, analyzes them with Amazon Bedrock AI, and automatically remediates EC2 instances.

## Architecture

```
Flask App (EC2) → CloudWatch Logs → Metric Filter → CloudWatch Alarm
                                                          |
                                                    Lambda (Bedrock AI)
                                                     /              \
                                          EC2 Reboot          SNS Notification
```

## Prerequisites

- AWS account with admin access
- AWS CLI configured
- Python 3.9+

## Quick Start

### 1. Launch EC2 with User Data

```bash
aws ec2 run-instances \
  --image-id resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --instance-type t2.micro \
  --iam-instance-profile Name=AI-AutoHeal-EC2-Profile \
  --user-data file://scripts/ec2_user_data.sh \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=AI-AutoHealing-Instance}]'
```

### 2. Create SNS Topic

```bash
aws sns create-topic --name AutoHealAlerts
aws sns subscribe --topic-arn arn:aws:sns:us-east-1:YOUR_ACCOUNT:AutoHealAlerts --protocol email --notification-endpoint your@email.com
```

### 3. Create Lambda

```bash
cd lambda && zip -r lambda.zip auto_heal_handler.py

aws lambda create-function \
  --function-name AI-AutoHeal-Handler \
  --runtime python3.14 \
  --role arn:aws:iam::YOUR_ACCOUNT:role/AI-AutoHeal-Lambda-Role \
  --handler auto_heal_handler.lambda_handler \
  --zip-file fileb://lambda.zip \
  --timeout 180

aws lambda update-function-configuration \
  --function-name AI-AutoHeal-Handler \
  --environment "Variables={INSTANCE_ID=i-xxxxx,LOG_GROUP_NAME=/app/ai-demo,SNS_TOPIC_ARN=arn:aws:sns:us-east-1:YOUR_ACCOUNT:AutoHealAlerts}"
```

### 4. Create Metric Filter & Alarm

```bash
aws logs put-metric-filter \
  --log-group-name /app/ai-demo \
  --filter-name ErrorCount \
  --filter-pattern "ERROR" \
  --metric-transformations metricName=ErrorRate,metricNamespace=AppMetrics,metricValue=1

aws cloudwatch put-metric-alarm \
  --alarm-name HighErrorRate-Alarm \
  --metric-name ErrorRate \
  --namespace AppMetrics \
  --statistic Sum \
  --period 60 \
  --threshold 5 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1 \
  --datapoints-to-alarm 1 \
  --alarm-actions arn:aws:sns:us-east-1:YOUR_ACCOUNT:AutoHealAlerts
```

### 5. Test

Access the app at `http://<EC2_PUBLIC_IP>` and click "Trigger Error" multiple times.

## Files

```
├── lambda/auto_heal_handler.py    # Lambda function with Bedrock AI
├── app/flask_app.py               # Flask demo application
├── app/requirements.txt           # Python dependencies
├── scripts/ec2_user_data.sh       # EC2 bootstrap script
├── scripts/deploy.sh              # Deployment script
├── scripts/test_workflow.sh       # Test automation
├── cloudformation/                # CloudFormation templates
├── docs/                          # Documentation
└── README.md                      # This file
```

## Costs

~$10/month (within AWS Free Tier limits for testing).
