# Troubleshooting Guide

## Common Issues and Fixes

### Flask App Not Running on Port 80
**Cause**: Flask tried to bind to port 80 (privileged port) while running as non-root `ec2-user` → Permission denied.
**Fix**: Changed port to 5000, installed Nginx as a reverse proxy on port 80.

### CloudWatch Log Group Not Appearing
**Causes**:
1. Log stream name had literal `{instance_id}` instead of actual instance ID
2. No log files being tracked for Flask app output
3. CloudWatch agent crashing due to invalid JSON config (unsupported `journald` section)
**Fix**: Replaced `{instance_id}` with actual instance ID, added Nginx logs, restructured to valid JSON config.

### Flask print("ERROR: ...") Logs Not Reaching CloudWatch
**Cause**: Python output buffering - `print()` is block-buffered when stdout is redirected to a file.
**Fix**: Added `Environment=PYTHONUNBUFFERED=1` to `flaskapp.service` and redirected stdout/stderr to `/var/log/flask/app.log`.

### Bedrock AI Model Not Available
**Cause**: Model IDs were wrong or require access request.
**Fix**: Use `amazon.nova-lite-v1:0` which works without access request.

### Alarm Stuck in INSUFFICIENT_DATA
**Cause**: No log data has been published to the metric yet.
**Fix**: Trigger some errors via the web app, then wait 1-2 minutes for the alarm to evaluate.

## Debugging Commands

```bash
# Check Flask app status
sudo systemctl status flaskapp

# Check Nginx status
sudo systemctl status nginx

# View Flask logs
sudo tail -f /var/log/flask/app.log

# View Nginx logs
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log

# Check CloudWatch agent
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -m ec2 -a status

# Check user data execution log
sudo cat /var/log/user-data.log

# Invoke Lambda manually
aws lambda invoke --function-name AI-AutoHeal-Handler --payload '{}' response.json

# Check CloudWatch logs
aws logs filter-log-events --log-group-name /app/ai-demo --filter-pattern "ERROR"

# Check alarm state
aws cloudwatch describe-alarms --alarm-names HighErrorRate-Alarm
```
