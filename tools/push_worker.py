"""Run in a private server container with a service-role env file, never in APK."""
import json
import os
import time
import urllib.error
import urllib.request

while True:
    try:
        request = urllib.request.Request(
            'http://127.0.0.1:8000/functions/v1/push-dispatch', data=b'{}',
            headers={'Authorization': 'Bearer ' + os.environ['SUPABASE_SERVICE_ROLE_KEY'],
                     'apikey': os.environ['SUPABASE_SERVICE_ROLE_KEY'],
                     'Content-Type': 'application/json'}, method='POST')
        with urllib.request.urlopen(request, timeout=25) as response:
            result = json.load(response)
        if any(result.values()):
            print(json.dumps(result), flush=True)
    except (OSError, ValueError):
        print('Push worker will retry', flush=True)
    time.sleep(5)
