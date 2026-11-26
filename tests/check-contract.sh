#!/usr/bin/env bash
set -euo pipefail

input="${1:-tests/fixtures/open-meteo-forecast.json}"

jq -e '
  (.current | type == "object" and (.temperature_2m | type == "number")) and
  (.hourly | has("time") and has("temperature_2m") and has("precipitation_probability") and has("wind_speed_10m") and has("weather_code")) and
  (.hourly.time | type == "array" and length > 0 and all(.[]; type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:00$"))) and
  ([.hourly.temperature_2m, .hourly.precipitation_probability, .hourly.wind_speed_10m, .hourly.weather_code] | all(type == "array" and length == $hourCount)) and
  (.hourly.temperature_2m | all(.[]; . == null or type == "number")) and
  (.hourly.precipitation_probability | all(.[]; . == null or (type == "number" and . >= 0 and . <= 100))) and
  (.hourly.wind_speed_10m | all(.[]; . == null or (type == "number" and . >= 0))) and
  (.hourly.weather_code | all(.[]; . == null or (type == "number" and . >= 0 and . <= 99))) and
  (.daily | has("time") and has("temperature_2m_max") and has("temperature_2m_min") and has("precipitation_probability_max") and has("wind_speed_10m_max") and has("weather_code")) and
  (.daily.time | type == "array" and length > 0 and all(.[]; type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$"))) and
  ([.daily.temperature_2m_max, .daily.temperature_2m_min, .daily.precipitation_probability_max, .daily.wind_speed_10m_max, .daily.weather_code] | all(type == "array" and length == $dayCount)) and
  (.daily.temperature_2m_max | all(.[]; type == "number")) and
  (.daily.temperature_2m_min | all(.[]; type == "number")) and
  (.daily.precipitation_probability_max | all(.[]; type == "number" and . >= 0 and . <= 100)) and
  (.daily.wind_speed_10m_max | all(.[]; type == "number" and . >= 0)) and
  (.daily.weather_code | all(.[]; . == null or (type == "number" and . >= 0 and . <= 99)))
' --argjson dayCount "$(jq '.daily.time | length' "$input")" \
  --argjson hourCount "$(jq '.hourly.time | length' "$input")" "$input" >/dev/null

echo "Weather response contract OK ($(jq '.daily.time | length' "$input") daily, $(jq '.hourly.time | length' "$input") hourly points)"
