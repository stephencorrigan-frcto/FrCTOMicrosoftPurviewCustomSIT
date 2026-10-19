import requests

resp = requests.get("https://api.example.com/prices", timeout=10)
if resp.status_code == 200:
    prices = resp.json()
    print(len(prices))