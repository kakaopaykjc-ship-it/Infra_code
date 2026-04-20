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
    markets = ",".join(f"KRW-{c['upbit']}" for c in COINS)

    # USD 시세 + 24h 고가/저가
    usd_url = (
        f"https://api.coingecko.com/api/v3/coins/markets"
        f"?vs_currency=usd&ids={ids}&price_change_percentage=24h"
    )
    # 업비트 KRW 실거래가 + 등락률
    upbit_url = f"https://api.upbit.com/v1/ticker?markets={markets}"

    usd_res = requests.get(usd_url, timeout=10)
    upbit_res = requests.get(upbit_url, timeout=10)
    usd_res.raise_for_status()
    upbit_res.raise_for_status()

    usd_data = {item["id"]: item for item in usd_res.json()}
    upbit_data = {item["market"]: item for item in upbit_res.json()}

    results = []
    for coin in COINS:
        cid = coin["id"]
        market = f"KRW-{coin['upbit']}"
        u = usd_data.get(cid, {})
        ub = upbit_data.get(market, {})

        krw_price = ub.get("trade_price", 0)
        opening_price = ub.get("opening_price", 0)
        change = ((krw_price - opening_price) / opening_price * 100) if opening_price else 0
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
