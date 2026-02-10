#!/bin/bash

# $1 is the ticker type passed from Waybar: "etf" or "stock"
ticker_type="$1"
url_file="/tmp/waybar_${ticker_type}_url"

if [[ -f "$url_file" ]]; then
  url=$(<"$url_file")
  if [[ -n "$url" ]]; then
    xdg-open "$url"
  else
    notify-send "Ticker: $ticker_type" "No URL found"
  fi
else
  notify-send "Ticker: $ticker_type" "URL file not found"
fi
