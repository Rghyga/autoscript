#!/usr/bin/env bash
set -euo pipefail
source /usr/local/katsu-panel/lib/common.sh
source /usr/local/katsu-panel/lib/db.sh

ssh::log_file() { printf '%s/ssh/%s.log\n' "$KATSU_CREATE_LOG" "$1"; }
ssh::save_file() { printf '%s/files/ssh-%s.txt\n' "$KATSU_WEBROOT" "$1"; }
ssh::password_hash() { openssl passwd -6 "$1"; }
ssh::exists() { id "$1" >/dev/null 2>&1; }
ssh::current_expire() { chage -l "$1" | awk -F': ' '/Account expires/{print $2}'; }
ssh::payload() { printf 'GET / HTTP/1.1[crlf]Host: [host][crlf]Connection: Upgrade[crlf]User-Agent: [ua][crlf]Upgrade: websocket[crlf][crlf]'; }
ssh::location() {
  local city region country
  city=$(curl -fsSL --max-time 5 https://ipinfo.io/city 2>/dev/null || true)
  region=$(curl -fsSL --max-time 5 https://ipinfo.io/region 2>/dev/null || true)
  country=$(curl -fsSL --max-time 5 https://ipinfo.io/country 2>/dev/null || true)
  printf '%s%s%s' "$city" "${region:+, $region}" "${country:+, $country}"
}

ssh::format_account() {
  local username="$1" password="$2" exp="$3" host ip loc saveurl
  host=$(read_domain); ip=$(public_ip); loc=$(ssh::location); saveurl="https://${host}/files/ssh-${username}.txt"
  cat <<TXT
┌─────────────────────────────────────────────────────────┐
                        SSH ACCOUNT
└─────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────┐
│  Username         : ${username}
│  Password         : ${password}
├─────────────────────────────────────────────────────────┤
│  IP               : ${ip}
│  Host             : ${host}
│  Location         : ${loc}
├─────────────────────────────────────────────────────────┤
│  Port OpenSSH     : 22
│  Port Dropbear    : 109
│  Port SSH WS      : 80
│  Port SSH SSL WS  : 443
│  Port SSL/TLS     : 443
├─────────────────────────────────────────────────────────┤
│  Format 80        : ${host}:80@${username}:${password}
│  Format 443       : ${host}:443@${username}:${password}
├─────────────────────────────────────────────────────────┤
│  Payload          : $(ssh::payload)
├─────────────────────────────────────────────────────────┤
│  Save Link Account: ${saveurl}
├─────────────────────────────────────────────────────────┤
│  Expired          : ${exp}
└─────────────────────────────────────────────────────────┘
TXT
}

ssh::write_log() {
  local username="$1" password="$2" exp="$3" limit="$4" note="$5"
  local file savefile content
  file=$(ssh::log_file "$username")
  savefile=$(ssh::save_file "$username")
  mkdir -p "$(dirname "$file")" "$(dirname "$savefile")"
  content=$(ssh::format_account "$username" "$password" "$exp")
  cat > "$file" <<LOG
Username      : $username
Password      : $password
Expired       : $exp
Limit IP      : $limit
Note          : $note
Domain        : $(read_domain)
IP            : $(public_ip)
Location      : $(ssh::location)
Payload       : $(ssh::payload)
Save Link     : https://$(read_domain)/files/ssh-${username}.txt
LOG
  printf '%s\n' "$content" > "$savefile"
  printf '%s\n' "$content"
}

ssh::create() {
  local username="$1" password="$2" days="$3" limit="$4" exp
  valid_username "$username" || { echo "Invalid username" >&2; return 1; }
  ssh::exists "$username" && { echo "SSH user exists" >&2; return 1; }
  exp=$(expire_date_days "$days")
  useradd -M -N -s /usr/sbin/nologin -e "$exp" -p "$(ssh::password_hash "$password")" "$username"
  echo "$limit" > "$KATSU_STATE/iplimits/ssh/$username"
  echo "$limit" > "/etc/xray/limit/ip/ssh/$username"
  db::upsert_ssh "$username" "$exp" "$limit" active manual
  ssh::write_log "$username" "$password" "$exp" "$limit" manual
}

ssh::delete() {
  local username="$1"
  ssh::exists "$username" || return 0
  pkill -KILL -u "$username" >/dev/null 2>&1 || true
  userdel -f "$username" >/dev/null 2>&1 || true
  rm -f "$KATSU_STATE/iplimits/ssh/$username" "$KATSU_STATE/suspended/ssh/$username" "/etc/xray/limit/ip/ssh/$username" "$(ssh::log_file "$username")" "$(ssh::save_file "$username")"
  db::delete_ssh "$username"
}

ssh::renew() {
  local username="$1" days="$2" row exp limit status note password
  ssh::exists "$username" || { echo "SSH user not found" >&2; return 1; }
  row=$(db::get_ssh "$username" || true)
  limit=$(awk -F'\t' '{print $3}' <<<"$row")
  status=$(awk -F'\t' '{print $4}' <<<"$row")
  note=$(awk -F'\t' '{print $6}' <<<"$row")
  password=$(awk -F': ' '/Password/{print $2}' "$(ssh::log_file "$username")" | head -n1)
  exp=$(date -u -d "+$days day" +%F)
  usermod -e "$exp" "$username"
  db::upsert_ssh "$username" "$exp" "${limit:-1}" "${status:-active}" "${note:-renew}"
  ssh::write_log "$username" "${password:-1}" "$exp" "${limit:-1}" "${note:-renew}"
}

ssh::trial() {
  local mins="$1" username password exp run_at
  while :; do username="trial$(random_string 4)"; ssh::exists "$username" || break; done
  password="1"
  exp=$(date -u -d "+$mins minutes" '+%b %d, %Y %H:%M UTC')
  useradd -M -N -s /usr/sbin/nologin -p "$(ssh::password_hash "$password")" "$username"
  echo 1 > "$KATSU_STATE/iplimits/ssh/$username"
  echo 1 > "/etc/xray/limit/ip/ssh/$username"
  db::upsert_ssh "$username" "$exp" 1 active trial
  ssh::write_log "$username" "$password" "$exp" 1 trial
  mkdir -p /etc/cron.d /usr/local/katsu-panel/scripts/generated
  cat > "/usr/local/katsu-panel/scripts/generated/trial-expire-ssh-${username}.sh" <<SCRIPT
#!/usr/bin/env bash
source /usr/local/katsu-panel/lib/common.sh
source /usr/local/katsu-panel/lib/db.sh
pkill -KILL -u "$username" >/dev/null 2>&1 || true
userdel -f "$username" >/dev/null 2>&1 || true
rm -f "$KATSU_STATE/iplimits/ssh/$username" "$KATSU_STATE/suspended/ssh/$username" "/etc/xray/limit/ip/ssh/$username" "$(ssh::log_file "$username")" "$(ssh::save_file "$username")"
db::delete_ssh "$username" >/dev/null 2>&1 || true
rm -f "/etc/cron.d/trial-expire-ssh-${username}" "\$0"
SCRIPT
  chmod +x "/usr/local/katsu-panel/scripts/generated/trial-expire-ssh-${username}.sh"
  run_at=$(date -u -d "+$mins minutes" '+%M %H %d %m *')
  echo "$run_at root /usr/local/katsu-panel/scripts/generated/trial-expire-ssh-${username}.sh" > "/etc/cron.d/trial-expire-ssh-${username}"
  printf '%s:%s\n' "$username" "$password"
}

ssh::set_iplimit() {
  local username="$1" limit="$2" row exp status note password
  ssh::exists "$username" || { echo "SSH user not found" >&2; return 1; }
  echo "$limit" > "$KATSU_STATE/iplimits/ssh/$username"
  echo "$limit" > "/etc/xray/limit/ip/ssh/$username"
  row=$(db::get_ssh "$username")
  exp=$(awk -F'\t' '{print $2}' <<<"$row")
  status=$(awk -F'\t' '{print $4}' <<<"$row")
  note=$(awk -F'\t' '{print $6}' <<<"$row")
  password=$(awk -F': ' '/Password/{print $2}' "$(ssh::log_file "$username")" | head -n1)
  db::upsert_ssh "$username" "$exp" "$limit" "${status:-active}" "${note:-manual}"
  ssh::write_log "$username" "${password:-1}" "$exp" "$limit" "${note:-manual}"
}

ssh::suspend() {
  local username="$1" reason="${2:-sharing}" row exp limit note
  ssh::exists "$username" || return 0
  passwd -l "$username" >/dev/null 2>&1 || true
  pkill -KILL -u "$username" >/dev/null 2>&1 || true
  echo "$reason" > "$KATSU_STATE/suspended/ssh/$username"
  row=$(db::get_ssh "$username")
  exp=$(awk -F'\t' '{print $2}' <<<"$row")
  limit=$(awk -F'\t' '{print $3}' <<<"$row")
  note=$(awk -F'\t' '{print $6}' <<<"$row")
  db::upsert_ssh "$username" "$exp" "$limit" suspended "$note"
}

ssh::unsuspend() {
  local username="$1" row exp limit note password
  ssh::exists "$username" || return 0
  passwd -u "$username" >/dev/null 2>&1 || true
  rm -f "$KATSU_STATE/suspended/ssh/$username"
  row=$(db::get_ssh "$username")
  exp=$(awk -F'\t' '{print $2}' <<<"$row")
  limit=$(awk -F'\t' '{print $3}' <<<"$row")
  note=$(awk -F'\t' '{print $6}' <<<"$row")
  password=$(awk -F': ' '/Password/{print $2}' "$(ssh::log_file "$username")" | head -n1)
  db::upsert_ssh "$username" "$exp" "$limit" active "$note"
  ssh::write_log "$username" "${password:-1}" "$exp" "$limit" "$note"
}

ssh::online_ip_count() {
  local username="$1"
  ss -tnp state established 2>/dev/null | awk -v u="$username" '$0 ~ /sshd/ && $0 ~ u {split($5,a,":"); print a[1]}' | sort -u | wc -l
}
