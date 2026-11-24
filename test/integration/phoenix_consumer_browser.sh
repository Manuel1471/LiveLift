#!/bin/sh
set -eu

repo_dir=$1
mode=$2
port=$LIVE_LIFT_CONSUMER_BROWSER_PORT
url="http://127.0.0.1:$port"
log="browser-$mode.log"

# Serve the output of assets.deploy without starting the development asset watchers.
PORT="$port" mix run --no-start --no-halt -e '
  endpoint = ConsumerLiftWeb.Endpoint
  config = Application.fetch_env!(:consumer_lift, endpoint)
  http = Keyword.put(config[:http], :port, String.to_integer(System.fetch_env!("PORT")))
  Application.put_env(:consumer_lift, endpoint, Keyword.merge(config, http: http, server: true, watchers: []))
  {:ok, _} = Application.ensure_all_started(:consumer_lift)
' >"$log" 2>&1 &
server=$!
trap 'kill "$server" 2>/dev/null || :; wait "$server" 2>/dev/null || :' EXIT

attempts=0
until grep -q 'Running ConsumerLiftWeb.Endpoint' "$log" &&
      curl -fsS --max-time 2 "$url/counter" >/dev/null 2>&1; do
  if ! kill -0 "$server" 2>/dev/null || [ "$attempts" -ge 60 ]; then
    cat "$log" >&2
    exit 1
  fi
  attempts=$((attempts + 1))
  sleep 1
done

node "$repo_dir/bench/consumer_browser.mjs" "$url" "$mode"
