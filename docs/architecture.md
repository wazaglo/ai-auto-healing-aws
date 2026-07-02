# Architecture Guide

## Overview

The AI-Driven Auto-Healing system uses a serverless architecture with Amazon Bedrock AI to automatically detect and remediate application failures.

## Components

### 1. Application Layer
- **EC2 Instance**: Runs a Flask web application behind Nginx reverse proxy
- **Nginx**: Serves as reverse proxy on port 80, forwarding to Flask on port 5000
- **Gunicorn**: WSGI server running Flask with 3 workers

### 2. Monitoring Layer
- **CloudWatch Agent**: Installed on EC2, streams application and Nginx logs to CloudWatch Logs
- **CloudWatch Logs Group**: `/app/ai-demo` - central log storage
- **Metric Filter**: `ErrorCount` - counts ERROR pattern occurrences, publishes to `AppMetrics/ErrorRate`

### 3. Alerting Layer
- **CloudWatch Alarm**: `HighErrorRate-Alarm` - triggers when ErrorRate Sum > 5 in 1 minute
- **SNS Topic**: `AutoHealAlerts` - notification channel for alarm and Lambda actions

### 4. Remediation Layer
- **Lambda Function**: `AI-AutoHeal-Handler` - triggered by EventBridge, fetches logs, calls Bedrock, executes fixes
- **Bedrock AI**: Analyzes logs using Amazon Nova Lite model for cost efficiency
- **EC2 Actions**: Reboot, stop, or notify based on AI analysis

## Data Flow

```
User clicks "Trigger Error"
       |
Flask logs ERROR to /var/log/flask/app.log
       |
CloudWatch Agent streams to /app/ai-demo
       |
Metric Filter counts ERROR occurrences
       |
AppMetrics/ErrorRate metric published
       |
CloudWatch Alarm evaluates: Sum > 5?
       |         |
      Yes       No (normal)
       |
Lambda invoked via EventBridge
       |
Lambda fetches logs from CloudWatch
       |
Bedrock AI analyzes logs
       |
AI suggests fix (reboot/scale/notify)
       |
Lambda executes remediation on EC2
       |
SNS sends notification email
```

## Key Design Decisions

- **Nova Lite over Claude**: No model access request needed, free tier eligible
- **Gunicorn over Flask dev server**: Production-ready, handles concurrent requests
- **Nginx reverse proxy**: Allows Flask to run on non-privileged port 5000 while serving on port 80
- **PYTHONUNBUFFERED=1**: Ensures print() output is immediately written to logs
- **Reboot as fallback**: When AI is unavailable, rebooting is the safest generic fix
