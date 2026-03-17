#!/usr/bin/env bash
set -euo pipefail
source /usr/local/katsu-panel/lib/common.sh

bw::summary_json() {
  local iface
  iface=$(katsu_iface)
  vnstat --json 2>/dev/null | jq --arg iface "$iface" '
    .interfaces[] | select(.name==$iface) | {
      today_total: ((.traffic.day[] | select(.date.day==(now|gmtime|.mday) and .date.month==(now|gmtime|.mon+1) and .date.year==(now|gmtime|.year+1900)) | (.tx + .rx)) // 0),
      month_total: ((.traffic.month[] | select(.date.month==(now|gmtime|.mon+1) and .date.year==(now|gmtime|.year+1900)) | (.tx + .rx)) // 0),
      total: (.traffic.total.rx + .traffic.total.tx)
    }'
}

bw::human() {
  numfmt --to=iec-i --suffix=B "$1" 2>/dev/null || echo "$1 B"
}
