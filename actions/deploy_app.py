import json
import os
import requests

with open('.github/pipeline.json') as fp:
    pipeline = json.load(fp)

app_name = os.getenv('app_name', '')
image_tag = os.getenv('image_tag', '')
credential_service = os.getenv('credential_service', '')
health_check_cmd = os.getenv('health_check_cmd', '')
gh_token = os.getenv('gh_token', '')

print(f'app_name: {app_name}')
print(f'image_tag: {image_tag}')
print(f'credential_service: {credential_service}')
print(f'health_check_cmd: {health_check_cmd}')

for env, locations in pipeline.items():
    print(env)
    for location, config in locations.items():
        enabled = config["enabled"]
        ip_address = config.get("ip_address", config['address'])
        staging_env = config["staging_env"]
        print(location)
        print(enabled)
        print(ip_address)
        if enabled:
            print(f"deploy application to {location}")
            url = 'https://api.github.com/repos/namachain/deployment/dispatches'
            headers = {
                'Content-type': 'application/json',
                'Accept': 'application/json',
                'authorization': f'Bearer { gh_token }'
            }
            data = {
                "event_type": "deploy", 
                "client_payload": {
                    "staging_env": staging_env,
                    "app_name": app_name, 
                    "image_tag": image_tag,
                    "ip_address": ip_address,
                    "credential_service": credential_service,
                    "health_check_cmd": health_check_cmd
                }
            }
            response = requests.post(url=url, headers=headers, json=data)
            print(f"status code: {response.status_code}")
