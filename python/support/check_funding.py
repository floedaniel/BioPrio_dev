"""
Check OpenAI account status and funding using only an API key.
Tries all available endpoints and reports whatever is accessible.
"""

import requests
from datetime import datetime, timedelta

OPENAI_API_KEY_FILE = r"C:\Users\dafl\Desktop\API keys\tore_vkm_openai.txt"


def load_api_key(file_path: str) -> str:
    try:
        with open(file_path, 'r') as f:
            return f.read().strip()
    except FileNotFoundError:
        raise SystemExit(f"❌ API key file not found: {file_path}")


def get(url, headers):
    """GET request, returns (status_code, data_or_none)."""
    try:
        r = requests.get(url, headers=headers, timeout=10)
        try:
            return r.status_code, r.json()
        except Exception:
            return r.status_code, r.text
    except requests.exceptions.RequestException as e:
        return None, str(e)


def section(title):
    print(f"\n{'=' * 50}")
    print(f"  {title}")
    print('=' * 50)


def check_account(api_key: str):
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }

    # ------------------------------------------------------------------ #
    # 1. Live quota check — make a 1-token call
    # ------------------------------------------------------------------ #
    section("QUOTA STATUS")
    r = requests.post(
        "https://api.openai.com/v1/chat/completions",
        headers=headers,
        json={"model": "gpt-4o-mini", "messages": [{"role": "user", "content": "hi"}], "max_tokens": 1},
        timeout=15,
    )
    if r.status_code == 200:
        print("✅ Account active — API calls working")
    elif r.status_code == 401:
        raise SystemExit("❌ Invalid API key")
    elif r.status_code == 429:
        code = r.json().get("error", {}).get("code", "")
        if code == "insufficient_quota":
            print("❌ OUT OF CREDITS — no quota remaining")
        else:
            msg = r.json().get("error", {}).get("message", "")
            print(f"⚠️  Rate limited (account active but throttled): {msg}")
    else:
        print(f"⚠️  Unexpected: {r.status_code} — {r.text[:200]}")

    # ------------------------------------------------------------------ #
    # 2. Subscription info (plan, limits, expiry)
    # ------------------------------------------------------------------ #
    section("SUBSCRIPTION")
    status, data = get("https://api.openai.com/dashboard/billing/subscription", headers)
    if status == 200 and isinstance(data, dict):
        plan = data.get("plan", {}).get("title", "Unknown")
        hard_limit = data.get("hard_limit_usd")
        soft_limit = data.get("soft_limit_usd")
        access_until = data.get("access_until")
        has_payment = data.get("has_payment_method")

        print(f"  Plan:              {plan}")
        if hard_limit is not None:
            print(f"  Hard limit:        ${hard_limit:.2f}/month")
        if soft_limit is not None:
            print(f"  Soft limit:        ${soft_limit:.2f}/month")
        if access_until:
            expiry = datetime.fromtimestamp(access_until).strftime("%Y-%m-%d")
            print(f"  Access until:      {expiry}")
        if has_payment is not None:
            print(f"  Payment method:    {'Yes' if has_payment else 'No'}")
    else:
        print(f"  Not available (status {status})")

    # ------------------------------------------------------------------ #
    # 3. Credit grants (prepaid balance — works for some account types)
    # ------------------------------------------------------------------ #
    section("CREDIT GRANTS (PREPAID)")
    status, data = get("https://api.openai.com/dashboard/billing/credit_grants", headers)
    if status == 200 and isinstance(data, dict):
        total = data.get("total_granted", 0)
        used = data.get("total_used", 0)
        remaining = data.get("total_available", 0)
        print(f"  Total granted:     ${total:.2f}")
        print(f"  Total used:        ${used:.2f}")
        print(f"  Remaining:         ${remaining:.2f}")
        grants = data.get("grants", {}).get("data", [])
        for grant in grants:
            expires_ts = grant.get("expires_at")
            available = grant.get("grant_amount", 0) - grant.get("used_amount", 0)
            expires = datetime.fromtimestamp(expires_ts).strftime("%Y-%m-%d") if expires_ts else "N/A"
            print(f"  └─ ${available:.2f} available, expires {expires}")
    else:
        print(f"  Not available (status {status})")

    # ------------------------------------------------------------------ #
    # 4. Usage — current month and previous month
    # ------------------------------------------------------------------ #
    section("USAGE (CURRENT & PREVIOUS MONTH)")
    today = datetime.today()
    first_this_month = today.replace(day=1)
    first_last_month = (first_this_month - timedelta(days=1)).replace(day=1)

    for label, start, end in [
        ("This month", first_this_month, today),
        ("Last month", first_last_month, first_this_month - timedelta(days=1)),
    ]:
        url = (
            f"https://api.openai.com/dashboard/billing/usage"
            f"?start_date={start.strftime('%Y-%m-%d')}"
            f"&end_date={end.strftime('%Y-%m-%d')}"
        )
        status, data = get(url, headers)
        if status == 200 and isinstance(data, dict):
            total_cents = data.get("total_usage", 0)  # in cents
            print(f"  {label}:    ${total_cents / 100:.4f}")
        else:
            print(f"  {label}:    Not available (status {status})")

    # ------------------------------------------------------------------ #
    # 5. Available models (confirms key scope)
    # ------------------------------------------------------------------ #
    section("AVAILABLE MODELS")
    status, data = get("https://api.openai.com/v1/models", headers)
    if status == 200 and isinstance(data, dict):
        models = sorted([m["id"] for m in data.get("data", [])])
        # Show GPT models only to keep output manageable
        gpt_models = [m for m in models if m.startswith("gpt")]
        print(f"  GPT models accessible: {len(gpt_models)}")
        for m in gpt_models:
            print(f"  └─ {m}")
    else:
        print(f"  Not available (status {status})")


api_key = load_api_key(OPENAI_API_KEY_FILE)
check_account(api_key)
