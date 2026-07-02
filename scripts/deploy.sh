#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}AI Auto-Healing AWS Deployment${NC}"
echo "==========================================="

echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v aws &> /dev/null; then
    echo -e "${RED}AWS CLI not found. Please install it.${NC}"
    exit 1
fi

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region)
echo -e "${GREEN}AWS Account: ${AWS_ACCOUNT_ID}${NC}"
echo -e "${GREEN}AWS Region: ${AWS_REGION}${NC}"

echo -e "${YELLOW}Finding EC2 instance...${NC}"
INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=AI-AutoHealing-Instance" "Name=instance-state-name,Values=running" \
    --query "Reservations[0].Instances[0].InstanceId" \
    --output text)

if [ "$INSTANCE_ID" = "None" ] || [ -z "$INSTANCE_ID" ]; then
    echo -e "${RED}No instance found. Please launch EC2 first.${NC}"
    exit 1
fi

echo -e "${GREEN}Found instance: ${INSTANCE_ID}${NC}"

echo -e "${YELLOW}Deploying Lambda function...${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR/lambda"
zip -r /tmp/lambda_function.zip auto_heal_handler.py
cd "$SCRIPT_DIR"

aws lambda update-function-code \
    --function-name AI-AutoHeal-Handler \
    --zip-file fileb:///tmp/lambda_function.zip \
    --publish > /dev/null

LAMBDA_ARN=$(aws lambda get-function \
    --function-name AI-AutoHeal-Handler \
    --query "Configuration.FunctionArn" \
    --output text)

echo -e "${GREEN}Lambda deployed: ${LAMBDA_ARN}${NC}"

aws lambda update-function-configuration \
    --function-name AI-AutoHeal-Handler \
    --environment "Variables={INSTANCE_ID=${INSTANCE_ID},LOG_GROUP_NAME=/app/ai-demo,SNS_TOPIC_ARN=arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:AutoHealAlerts}" > /dev/null

echo -e "${GREEN}Environment variables updated${NC}"

echo -e "${GREEN}Deployment complete!${NC}"
