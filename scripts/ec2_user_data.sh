#!/bin/bash
set -e

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "Updating system..."
dnf update -y
dnf install -y python3 python3-pip nginx git

echo "Installing Python packages..."
pip3 install flask boto3 gunicorn

echo "Creating Flask application..."
mkdir -p /var/log/flask
chmod 755 /var/log/flask

cat > /home/ec2-user/app.py << 'PYEOF'
from flask import Flask, jsonify, render_template_string
import datetime
import random
import os
import logging

logging.basicConfig(
    filename='/var/log/flask/app.log',
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

app = Flask(__name__)

HTML = '''
<!DOCTYPE html>
<html>
<head>
    <title>AI Auto-Healing Demo</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; background: #f0f0f0; }
        .container { background: white; padding: 30px; border-radius: 10px; max-width: 600px; margin: 0 auto; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
        .status { padding: 20px; margin: 20px 0; border-radius: 8px; font-size: 18px; }
        .healthy { background: #90EE90; }
        .error { background: #FF6B6B; color: white; }
        button { padding: 15px 30px; font-size: 16px; cursor: pointer; border: none; border-radius: 5px; margin: 5px; transition: transform 0.2s; }
        button:hover { transform: scale(1.05); }
        .btn-error { background: #FF6B6B; color: white; }
        .btn-reset { background: #4CAF50; color: white; }
        .btn-health { background: #2196F3; color: white; }
        .metrics { margin-top: 20px; padding: 15px; background: #f8f9fa; border-radius: 5px; }
        .badge { display: inline-block; padding: 3px 8px; border-radius: 3px; font-size: 12px; }
        .badge-success { background: #4CAF50; color: white; }
        .badge-danger { background: #FF6B6B; color: white; }
    </style>
</head>
<body>
    <div class="container">
        <h1>AI Auto-Healing Demo</h1>
        <p><strong>Instance:</strong> {{ instance_id }}</p>
        <p><strong>Time:</strong> {{ current_time }}</p>
        <div class="status {{ status_class }}">
            <h2>Status: {{ status }}</h2>
            <p>{{ message }}</p>
        </div>
        <div>
            <button class="btn-error" onclick="location.href='/trigger-error'">Trigger Error</button>
            <button class="btn-reset" onclick="location.href='/'">Reset</button>
            <button class="btn-health" onclick="location.href='/health'">Health</button>
        </div>
        <div class="metrics">
            <h3>Metrics</h3>
            <p>Error Rate: <span class="badge {{ 'badge-danger' if error_rate > 5 else 'badge-success' }}">{{ error_rate }}%</span></p>
            <p>Total Requests: {{ total_requests }}</p>
            <p>Total Errors: {{ error_count }}</p>
        </div>
        <p style="margin-top: 20px; font-size: 12px; color: #666;">Auto-Healing will trigger when error rate exceeds 5%</p>
    </div>
</body>
</html>
'''

error_count = 0
total_requests = 0

@app.route('/')
def home():
    global total_requests
    total_requests += 1
    error_rate = get_error_rate()
    return render_template_string(HTML,
        instance_id=get_instance_id(),
        current_time=datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
        status='HEALTHY', status_class='healthy',
        message='All systems operational!',
        error_rate=error_rate, total_requests=total_requests, error_count=error_count)

@app.route('/trigger-error')
def trigger_error():
    global error_count, total_requests
    total_requests += 1
    error_count += 1
    error_type = random.choice(['timeout', 'database', 'memory', 'config', 'connection'])
    logging.error(f"ERROR: {error_type} error occurred! Error count: {error_count}")
    print(f"ERROR: {error_type} error occurred!")
    error_rate = get_error_rate()
    return render_template_string(HTML,
        instance_id=get_instance_id(),
        current_time=datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
        status='ERROR', status_class='error',
        message=f'{error_type.upper()} error simulated!',
        error_rate=error_rate, total_requests=total_requests, error_count=error_count), 500

@app.route('/health')
def health():
    return jsonify({
        'status': 'healthy' if get_error_rate() < 5 else 'unhealthy',
        'error_rate': get_error_rate(),
        'total_requests': total_requests,
        'error_count': error_count,
        'instance_id': get_instance_id(),
        'timestamp': datetime.datetime.now().isoformat()
    })

def get_error_rate():
    if total_requests == 0:
        return 0
    return round((error_count / total_requests) * 100, 1)

def get_instance_id():
    try:
        return os.popen('curl -s http://169.254.169.254/latest/meta-data/instance-id').read().strip()
    except:
        return 'unknown'

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
PYEOF

chown ec2-user:ec2-user /home/ec2-user/app.py

echo "Configuring systemd service..."
cat > /etc/systemd/system/flaskapp.service << 'UNITEOF'
[Unit]
Description=Flask AI Demo App
After=network.target

[Service]
ExecStart=/usr/local/bin/gunicorn --workers 3 --bind 0.0.0.0:5000 app:app
WorkingDirectory=/home/ec2-user
Restart=always
User=ec2-user
Environment=PYTHONUNBUFFERED=1
StandardOutput=append:/var/log/flask/app.log
StandardError=append:/var/log/flask/app.log

[Install]
WantedBy=multi-user.target
UNITEOF

systemctl daemon-reload
systemctl enable flaskapp
systemctl start flaskapp

echo "Configuring Nginx reverse proxy..."
cat > /etc/nginx/nginx.conf << 'NGINXEOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 1024;
}

http {
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 4096;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    server {
        listen 80 default_server;
        listen [::]:80 default_server;
        server_name _;

        location / {
            proxy_pass http://127.0.0.1:5000;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}
NGINXEOF

systemctl enable nginx
systemctl restart nginx

echo "Installing CloudWatch agent..."
dnf install -y amazon-cloudwatch-agent

INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json << 'CWEOF'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/flask/app.log",
            "log_group_name": "/app/ai-demo",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/nginx/access.log",
            "log_group_name": "/app/ai-demo",
            "log_stream_name": "{instance_id}-nginx-access",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/nginx/error.log",
            "log_group_name": "/app/ai-demo",
            "log_stream_name": "{instance_id}-nginx-error",
            "timezone": "UTC"
          }
        ]
      }
    }
  }
}
CWEOF

sed -i "s/{instance_id}/$INSTANCE_ID/g" /opt/aws/amazon-cloudwatch-agent/etc/config.json

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json -s

echo "Deployment complete!"
echo "App should be accessible at http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
