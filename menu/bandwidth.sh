#!/usr/bin/env bash
set -euo pipefail
source /usr/local/katsu-panel/lib/common.sh
source /usr/local/katsu-panel/lib/ui.sh
source /usr/local/katsu-panel/lib/bandwidth.sh

ui::clear
ui::title 'BANDWIDTH MONITOR'
summary=$(bw::summary_json 2>/dev/null || echo '{}')
ui::kv 'Today usage' "$(bw::human "$(jq -r '.today_total // 0' <<<"$summary")")"
ui::kv 'Monthly usage' "$(bw::human "$(jq -r '.month_total // 0' <<<"$summary")")"
ui::kv 'Total usage' "$(bw::human "$(jq -r '.total // 0' <<<"$summary")")"
ui::line
vnstat -i "$(katsu_iface)" | sed -n '1,20p'
ui::pause
