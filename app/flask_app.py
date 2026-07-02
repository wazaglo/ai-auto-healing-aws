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
        button {
            padding: 15px 30px;
            font-size: 16px;
            cursor: pointer;
            border: none;
            border-radius: 5px;
            margin: 5px;
            transition: transform 0.2s;
        }
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

        <p style="margin-top: 20px; font-size: 12px; color: #666;">
            Auto-Healing will trigger when error rate exceeds 5%
        </p>
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
        status='HEALTHY',
        status_class='healthy',
        message='All systems operational!',
        error_rate=error_rate,
        total_requests=total_requests,
        error_count=error_count
    )

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
        status='ERROR',
        status_class='error',
        message=f'{error_type.upper()} error simulated!',
        error_rate=error_rate,
        total_requests=total_requests,
        error_count=error_count
    ), 500

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
