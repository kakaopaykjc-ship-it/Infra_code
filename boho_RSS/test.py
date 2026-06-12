import os
import requests

WEBHOOK_URL = os.environ.get("MATTERMOST_WEBHOOK_URL", "")

res = requests.post(
    WEBHOOK_URL,
    json={"text": "보호나라 RSS Python 전송 테스트"},
    timeout=10
)

print(res.status_code)
print(res.text)

