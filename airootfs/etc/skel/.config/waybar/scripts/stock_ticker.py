#!/usr/bin/env python3
import yfinance as yf
import os
import json
from time import sleep

# Config
SYMBOLS = ["AAPL", "TSLA", "AMZN", "MSFT", "NVDA", "META", "GOOG", "NFLX", "INTC", "AMD"]
OFFSET_FILE = "/tmp/waybar_stock_ticker_offset_group"

def fetch_all_changes(symbols):
    changes = []
    for sym in symbols:
        try:
            hist = yf.download(sym, period="2d", interval="1d", progress=False)
            if hist.empty or "Close" not in hist.columns or len(hist) < 2:
                changes.append((sym, None, None))
                continue
            yesterday = hist["Close"].iloc[-2].item()
            today = hist["Close"].iloc[-1].item()
            pct = (today - yesterday) / yesterday * 100
            changes.append((sym, pct, today))
        except Exception:
            changes.append((sym, None, None))
    return changes

def read_offset():
    if os.path.exists(OFFSET_FILE):
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
    all_changes = fetch_all_changes(SYMBOLS)

    valid = [(s, p, pr) for s, p, pr in all_changes if p is not None and pr is not None]
    if not valid:
        print(json.dumps({
            "text": "No data available",
            "tooltip": "All stock data is unavailable",
            "class": "stock-neutral"
        }))
        return

    sorted_changes = sorted(valid, key=lambda x: x[1])
    group_type = "bottom" if (offset % 2 == 0) else "top"

    if group_type == "bottom":
        selected = sorted_changes[:5]
        css_class = "stock-negative"
    else:
        selected = sorted_changes[-5:]
        css_class = "stock-positive"

    display_text = " | ".join(format_ticker(s, p) for s, p, pr in selected)
    tooltip_text = "\n".join(format_tooltip(s, p, pr) for s, p, pr in selected)
    first_symbol = selected[0][0]  # Use for on-click action

    print(json.dumps({
        "text": display_text,
        "tooltip": tooltip_text,
        "class": css_class,
    }))
    write_offset(offset + 1)
    # Save the stock URL to a known location
    with open("/tmp/waybar_stock_url", "w") as f:
        f.write(f"https://finance.yahoo.com/quote/{first_symbol}")

if __name__ == "__main__":
        main()
