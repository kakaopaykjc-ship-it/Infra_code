import requests
from config import TELEGRAM_TOKEN, GROUP_CHAT_ID

COINS = [
    {"id": "bitcoin",                  "name": "비트코인 (BTC)",          "upbit": "BTC"},
    {"id": "ethereum",                 "name": "이더리움 (ETH)",           "upbit": "ETH"},
    {"id": "solana",                   "name": "솔라나 (SOL)",             "upbit": "SOL"},
    {"id": "ripple",                   "name": "리플 (XRP)",               "upbit": "XRP"},
    {"id": "ethereum-name-service",    "name": "이더리움 네임서비스 (ENS)", "upbit": "ENS"},
]


def get_crypto_prices():
    ids = ",".join(c["id"] for c in COINS)

    # USD 시세 + 24h 고가/저가/등락률
    usd_url = (
        f"https://api.coingecko.com/api/v3/coins/markets"
        f"?vs_currency=usd&ids={ids}&price_change_percentage=24h"
    )
    # KRW 현재 시세
    krw_url = (
        f"https://api.coingecko.com/api/v3/simple/price"
        f"?ids={ids}&vs_currencies=krw"
    )

    usd_res = requests.get(usd_url, timeout=10)
    krw_res = requests.get(krw_url, timeout=10)
    usd_res.raise_for_status()
    krw_res.raise_for_status()

    usd_data = {item["id"]: item for item in usd_res.json()}
    krw_data = krw_res.json()

    results = []
    for coin in COINS:
        cid = coin["id"]
        u = usd_data.get(cid, {})
        krw_price = krw_data.get(cid, {}).get("krw", 0)

        change = u.get("price_change_percentage_24h", 0) or 0
        change_str = f"+{change:.2f}%" if change >= 0 else f"{change:.2f}%"
        arrow = "📈" if change >= 0 else "📉"

        results.append({
            "name": coin["name"],
            "usd": u.get("current_price", 0),
            "krw": krw_price,
            "high": u.get("high_24h", 0),
            "low": u.get("low_24h", 0),
            "change": change_str,
            "arrow": arrow,
            "upbit": f"https://upbit.com/exchange?code=CRIX.UPBIT.KRW-{coin['upbit']}",
        })

    return results


def format_message(coins):
    lines = ["💰 암호화폐 시세 알림\n"]
    for c in coins:
        lines.append(
            f"{c['arrow']} {c['name']}\n"
            f"  💵 USD: ${c['usd']:,.4f}\n"
            f"  🇰🇷 KRW: ₩{c['krw']:,}\n"
            f"  📊 등락률: {c['change']}\n"
            f"  🔺 24h 고가: ${c['high']:,.4f}\n"
            f"  🔻 24h 저가: ${c['low']:,.4f}\n"
            f"  🔗 업비트: {c['upbit']}\n"
        )
    return "\n".join(lines)


def send_telegram(message):
    url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage"
    payload = {"chat_id": GROUP_CHAT_ID, "text": message}
    res = requests.post(url, data=payload, timeout=10)
    res.raise_for_status()


def main():
    coins = get_crypto_prices()
    message = format_message(coins)
    send_telegram(message)
    print("시세 알림 전송 완료")


if __name__ == "__main__":
    main()
