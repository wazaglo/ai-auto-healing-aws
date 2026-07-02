#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Testing AI Auto-Healing Workflow${NC}"
echo "==========================================="

INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=AI-AutoHealing-Instance" "Name=instance-state-name,Values=running" \
    --query "Reservations[0].Instances[0].InstanceId" \
    --output text)

PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids $INSTANCE_ID \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --output text)

echo -e "${YELLOW}1. Checking application health...${NC}"
curl -s http://$PUBLIC_IP/health | python3 -m json.tool
echo ""

echo -e "${YELLOW}2. Triggering errors...${NC}"
for i in {1..6}; do
    echo "   Triggering error $i..."
    curl -s http://$PUBLIC_IP/trigger-error > /dev/null
    sleep 1
done
echo ""

echo -e "${YELLOW}3. Checking error rate...${NC}"
curl -s http://$PUBLIC_IP/health | python3 -m json.tool
echo ""

echo -e "${YELLOW}4. Checking CloudWatch logs...${NC}"
aws logs filter-log-events \
    --log-group-name /app/ai-demo \
    --filter-pattern "ERROR" \
    --limit 5 \
    --query 'events[*].[message,timestamp]' \
    --output table

echo ""
echo -e "${YELLOW}5. Checking CloudWatch metric...${NC}"
aws cloudwatch list-metrics --namespace AppMetrics --metric-name ErrorRate --output table

echo ""
echo -e "${YELLOW}6. Checking CloudWatch alarm...${NC}"
aws cloudwatch describe-alarms --alarm-names HighErrorRate-Alarm \
    --query 'MetricAlarms[0].[AlarmName,StateValue,Threshold]' \
    --output table

echo ""
echo -e "${YELLOW}7. Testing Lambda directly...${NC}"
aws lambda invoke \
    --function-name AI-AutoHeal-Handler \
    --payload "{\"instance_id\": \"$INSTANCE_ID\"}" \
    --region us-east-1 \
    /tmp/lambda-test.json > /dev/null
python3 -m json.tool /tmp/lambda-test.json

echo ""
echo -e "${GREEN}Test complete!${NC}"
