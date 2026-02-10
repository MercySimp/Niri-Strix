#!/usr/bin/env python3
import yfinance as yf
from os import path
from json import dumps

# Config
SYMBOLS = ["^VIX", "^GSPC", "GC=F", "^IXIC", "BTC-USD"]
OFFSET_FILE = "/tmp/waybar_etf_ticker_offset_group"

def fetch_change(symbol):
    try:
        hist = yf.download(symbol, period="2d", interval="1d", progress=False)
        if hist.empty or "Close" not in hist.columns or len(hist) < 2:
            return symbol, None, None
        yesterday = hist["Close"].iloc[-2].item()
        today = hist["Close"].iloc[-1].item()
        pct = (today - yesterday) / yesterday * 100
        return symbol, pct, today
    except Exception:
        return symbol, None, None

def read_offset():
    if path.exists(OFFSET_FILE):
        try:
            return int(open(OFFSET_FILE).read().strip())
        except Exception:
            pass
    return 0

def write_offset(offset):
    with open(OFFSET_FILE, "w") as f:
        f.write(str(offset))

def format_ticker(symbol, pct):
    if pct is None:
        return f"{symbol}: N/A"
    arrow = "▲" if pct > 0 else "▼" if pct < 0 else "-"
    sign = "+" if pct >= 0 else ""
    return f"{symbol}: {arrow}{sign}{pct:.2f}%"

def format_tooltip(symbol, pct, price):
    if pct is None or price is None:
        return f"{symbol}: N/A"
    arrow = "▲" if pct > 0 else "▼" if pct < 0 else "-"
    sign = "+" if pct >= 0 else ""
    return f"{symbol}: {arrow}{sign}{pct:.2f}% (${price:.2f})"

def main():
    offset = read_offset()
    index = offset % len(SYMBOLS)
    symbol = SYMBOLS[index]

    sym, pct, price = fetch_change(symbol)

    css_class = "stock-neutral"
    if pct is not None:
        css_class = "stock-positive" if pct > 0 else "stock-negative" if pct < 0 else "stock-neutral"

    print(dumps({
        "text": format_ticker(sym, pct),
        "tooltip": format_tooltip(sym, pct, price),
        "class": css_class,
    }))

    write_offset(offset + 1)

    # Save the stock URL to a known location
    with open("/tmp/waybar_etf_url", "w") as f:
        f.write(f"https://finance.yahoo.com/quote/{symbol}")

if __name__ == "__main__":
    main()
