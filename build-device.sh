#!/usr/bin/env bash
set -euo pipefail

: "${CONNECT_IQ_SDK_HOME:?Set CONNECT_IQ_SDK_HOME to the Connect IQ SDK directory}"
: "${DEVELOPER_KEY:?Set DEVELOPER_KEY to your developer key .der file}"

mkdir -p bin
"$CONNECT_IQ_SDK_HOME/bin/monkeyc" \
  -f monkey.jungle \
  -d fenix847mm \
  -o bin/MeteoSwissWeather-device.prg \
  -y "$DEVELOPER_KEY" \
  -r \
  -w
