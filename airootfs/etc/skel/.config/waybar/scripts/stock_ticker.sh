#!/bin/bash

# List of stock symbols (comma-separated)
SYMBOLS="AAPL,TSLA,AMZN,MSFT,NVDA"

# Temp file for scroll offset (self-contained)
OFFSET_FILE="/tmp/$(basename "$0")_offset"

# Fetch stock data from Yahoo Finance
RESPONSE=$(curl -s -H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36' "https://query1.finance.yahoo.com/v7/finance/quote?symbols=$SYMBOLS")


# Parse each stock's symbol and % change
TICKER=""
for sym in $(echo $SYMBOLS | tr ',' ' '); do
    CHANGE=$(echo "$REPONSE" | jq -r --arg sym "$sym" '.quoteResponse.result[] | select(.symbol == $sym) | .regularMarketChangePercent')
    if [[ "$CHANGE" != "null" ]]; then
        # Format: Symbol: +1.23% or -0.87%
        printf -v ENTRY "%s: %+0.2f%% | " "$sym" "$CHANGE"
        TICKER+="$ENTRY"
    fi
done

# Fallback if API failed
[[ -z "$TICKER" ]] && TICKER=" No data available | "

# Read scroll offset
if [[ -f "$OFFSET_FILE" ]]; then
    OFFSET=$(<"$OFFSET_FILE")
else
    OFFSET=0
fi

# Ensure offset is numeric
if ! [[ "$OFFSET" =~ ^[0-9]+$ ]]; then
    OFFSET=0
fi

# Scroll logic
LEN=${#TICKER}
OFFSET=$((OFFSET % LEN))
SCROLLED="${TICKER:OFFSET}${TICKER:0:OFFSET}"
echo "${SCROLLED:0:60}"  # Output 60-character slice

# Save next offset
echo $(( (OFFSET + 1) % LEN )) > "$OFFSET_FILE"
