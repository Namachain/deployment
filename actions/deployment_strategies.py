import json
import os
import requests


print(f"current directory: {os.getcwd()}")

repository = os.getenv("GITHUB_REPOSITORY")
branch = os.getenv("branch")
gh_token = os.getenv("gh_token")

url = f'https://raw.githubusercontent.com/{repository}/{branch}/.github/pipeline.json'
headers = {
    'Accept': 'application/json',
    'authorization': f'Bearer { gh_token }'
}

print(f"URL: {url}")
response = requests.get(url=url, headers=headers)
print(f"Status code: {response.status_code}")
response.raise_for_status()
pipeline = response.json()

app_name = os.getenv('app_name', '')
image_tag = os.getenv('image_tag', '')
credential_service = os.getenv('credential_service', '')
health_check_cmd = os.getenv('health_check_cmd', '')
staging_env_from_input = os.getenv('staging_env', '')

print(f'app_name: {app_name}')
print(f'image_tag: {image_tag}')
print(f'credential_service: {credential_service}')
print(f'health_check_cmd: {health_check_cmd}')

matrix_include = []
for env, locations in pipeline.items():
    print(env)
    for location, config in locations.items():
        ip_address = config.get("ip_address",config.get('address'))
        staging_env = config["staging_env"]
        enabled = config["enabled"]
        if staging_env_from_input:
            enabled = staging_env_from_input == staging_env
        print(location)
        print(enabled)
        print(ip_address)
        if enabled:
            matrix_include.append({
                "staging_env": staging_env,
                "ip_address": ip_address,
                "app_name": app_name,
                "image_tag": image_tag,
                "credential_service": credential_service,
                "health_check_cmd": health_check_cmd
            })

print("Strategy matrix:")
print(f"{matrix_include}")
print(f"::set-output name=matrix_include::{json.dumps(matrix_include)}")
