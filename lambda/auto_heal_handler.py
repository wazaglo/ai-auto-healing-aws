import json
import boto3
import os
import time
import re
from datetime import datetime

logs_client = boto3.client('logs')
ec2_client = boto3.client('ec2')
sns_client = boto3.client('sns')
bedrock_client = boto3.client('bedrock-runtime', region_name='us-east-1')

SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN', '')
LOG_GROUP_NAME = os.environ.get('LOG_GROUP_NAME', '/app/ai-demo')
INSTANCE_ID = os.environ.get('INSTANCE_ID', '')

def lambda_handler(event, context):
    print(f"Received event: {json.dumps(event)}")

    instance_id = get_instance_id(event)

    if not instance_id:
        return error_response("No instance ID available. Set INSTANCE_ID environment variable.")

    print(f"Fetching logs from {LOG_GROUP_NAME}")
    logs = get_recent_logs(LOG_GROUP_NAME, minutes=5)

    print("Analyzing logs with Bedrock AI...")
    ai_analysis = analyze_logs_with_bedrock(logs)
    print(f"AI Analysis: {ai_analysis}")

    action = parse_ai_response(ai_analysis, instance_id)
    print(f"Action to take: {action}")

    if action['priority'] in ['HIGH', 'MEDIUM']:
        success = execute_remediation(action, instance_id)
        if success:
            send_notification(action, instance_id)
            return success_response(action, instance_id)

    return success_response(action, instance_id, action_taken=False)

def get_instance_id(event):
    instance_id = INSTANCE_ID or event.get('instance_id', '')

    if not instance_id and 'trigger' in event and 'dimensions' in event['trigger']:
        for dim in event['trigger']['dimensions']:
            if dim.get('name') == 'InstanceId':
                instance_id = dim.get('value')
                break

    return instance_id

def get_recent_logs(log_group, minutes=5):
    end_time = int(round(time.time() * 1000))
    start_time = end_time - (minutes * 60 * 1000)

    try:
        log_group = log_group.strip()
        response = logs_client.filter_log_events(
            logGroupName=log_group,
            startTime=start_time,
            endTime=end_time,
            limit=100
        )

        events = response.get('events', [])
        log_messages = [event['message'] for event in events]

        if not log_messages:
            return "No recent logs found"

        return '\n'.join(log_messages[-50:])

    except Exception as e:
        print(f"Error fetching logs: {e}")
        return "No logs available"

def analyze_logs_with_bedrock(logs):
    prompt = f"""
    You are an AWS expert. Analyze these application logs and suggest a fix.

    Logs:
    {logs}

    Provide your response in this EXACT format:
    ISSUE: [Brief description of the problem]
    ROOT_CAUSE: [What's causing this]
    PRIORITY: [HIGH/MEDIUM/LOW]
    SUGGESTED_FIX: [Specific action to take]

    Example response:
    ISSUE: High error rate detected in application
    ROOT_CAUSE: Database connection pool exhausted
    PRIORITY: HIGH
    SUGGESTED_FIX: Reboot EC2 instance to reset connections
    """

    models_to_try = [
        'amazon.nova-lite-v1:0',
        'amazon.nova-micro-v1:0'
    ]

    for model_id in models_to_try:
        try:
            print(f"Trying model: {model_id}")

            response = bedrock_client.converse(
                modelId=model_id,
                messages=[
                    {
                        "role": "user",
                        "content": [
                            {
                                "text": prompt
                            }
                        ]
                    }
                ],
                inferenceConfig={
                    "maxTokens": 500,
                    "temperature": 0.5
                }
            )

            if 'output' in response and 'message' in response['output']:
                content = response['output']['message']['content']
                if content and len(content) > 0 and 'text' in content[0]:
                    result = content[0]['text']
                    print(f"Success with {model_id}")
                    return result

        except Exception as e:
            print(f"Model {model_id} failed: {e}")
            continue

    return """
    ISSUE: Unable to analyze logs with AI
    ROOT_CAUSE: AI model unavailable
    PRIORITY: MEDIUM
    SUGGESTED_FIX: Reboot the instance as a precaution
    """

def parse_ai_response(ai_response, instance_id):
    action = {
        'priority': 'LOW',
        'fix': 'No action needed',
        'resource': instance_id,
        'command': None,
        'action_type': 'notify_only'
    }

    priority_match = re.search(r'PRIORITY:\s*(\w+)', ai_response, re.IGNORECASE)
    if priority_match:
        action['priority'] = priority_match.group(1).upper()

    fix_match = re.search(r'SUGGESTED_FIX:\s*(.+?)(?:\n|$)', ai_response, re.IGNORECASE)
    if fix_match:
        action['fix'] = fix_match.group(1).strip()

    root_cause_match = re.search(r'ROOT_CAUSE:\s*(.+?)(?:\n|$)', ai_response, re.IGNORECASE)
    if root_cause_match:
        action['root_cause'] = root_cause_match.group(1).strip()

    fix_lower = action['fix'].lower()
    if 'reboot' in fix_lower or 'restart' in fix_lower:
        action['action_type'] = 'reboot'
    elif 'scale' in fix_lower or 'increase' in fix_lower:
        action['action_type'] = 'scale'
    elif 'reset' in fix_lower or 'clear' in fix_lower:
        action['action_type'] = 'reset'
    else:
        action['action_type'] = 'notify_only'

    return action

def execute_remediation(action, instance_id):
    action_type = action.get('action_type', 'notify_only')

    try:
        if action_type == 'reboot':
            print(f"Rebooting instance: {instance_id}")
            ec2_client.reboot_instances(InstanceIds=[instance_id])
            print(f"Reboot initiated for {instance_id}")
            return True

        elif action_type == 'stop':
            print(f"Stopping instance: {instance_id}")
            ec2_client.stop_instances(InstanceIds=[instance_id])
            return True

        elif action_type == 'scale':
            print(f"Scaling instance: {instance_id}")
            return True

        else:
            print(f"Notification only for instance: {instance_id}")
            return True

    except Exception as e:
        print(f"Remediation failed: {e}")
        return False

def send_notification(action, instance_id):
    if not SNS_TOPIC_ARN:
        print("No SNS topic ARN configured")
        return

    message = f"""
AWS AUTO-HEALING ALERT

INSTANCE: {instance_id}
PRIORITY: {action['priority']}

ISSUE:
{action['fix']}

ROOT CAUSE:
{action.get('root_cause', 'Not identified')}

ACTION TAKEN:
{action.get('action_type', 'Notification only').upper()}

TIMESTAMP: {datetime.utcnow().isoformat()}
"""

    try:
        response = sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f'Auto-Healing: {action["action_type"].upper()} on {instance_id}',
            Message=message
        )
        print(f"Notification sent: {response['MessageId']}")
        return True
    except Exception as e:
        print(f"Failed to send notification: {e}")
        return False

def success_response(action, instance_id, action_taken=True):
    if action_taken:
        message = f"Auto-remediation executed: {action['fix']}"
    else:
        message = "No action needed"

    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': message,
            'instance': instance_id,
            'action': action
        })
    }

def error_response(error_message):
    return {
        'statusCode': 400,
        'body': json.dumps({
            'error': error_message
        })
    }
