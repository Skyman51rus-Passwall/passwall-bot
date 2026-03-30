#!/bin/sh

echo ""
echo "========================================="
echo "  PassWall Bot Installer"
echo "========================================="
echo ""

# Запрашиваем данные
printf "Bot token from @BotFather: "
read BOT_TOKEN

printf "Your Chat ID from @userinfobot: "
read CHAT_ID

printf "PassWall version 1 or 2: "
read PW_VER

printf "Check interval in minutes default 5: "
read CHECK_INT
[ -z "$CHECK_INT" ] && CHECK_INT=5

printf "Max latency ms default 1500: "
read MAX_LAT
[ -z "$MAX_LAT" ] && MAX_LAT=1500

echo ""
echo "Installing..."

# Конфиг
cat > /root/passwall-bot.conf << CFG
CHECK_INTERVAL=$CHECK_INT
MAX_LATENCY=$MAX_LAT
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
CFG

# Основной скрипт мониторинга
if [ "$PW_VER" = "2" ]; then
cat > /root/passwall-auto-switch.sh << 'SCRIPT'
#!/bin/sh
CONFIG="/root/passwall-bot.conf"
[ -f "$CONFIG" ] && . "$CONFIG"
MAX_LATENCY=${MAX_LATENCY:-1500}
SLEEP=10
LOCK_FILE="/tmp/passwall-auto-switch.lock"
TEST_URL="https://www.gstatic.com/generate_204"
LOG_FILE="/var/log/passwall-switch.log"
log_msg() { echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" | tee -a "$LOG_FILE"; logger -t internet-detector "$1"; }
if [ -f "$LOCK_FILE" ]; then exit 0; fi
touch "$LOCK_FILE"
trap "rm -f $LOCK_FILE" EXIT
CURRENT=$(uci -q get passwall2.@global[0].node)
[ -z "$CURRENT" ] && CURRENT=$(uci -q get passwall2.@global[0].default_node)
TIMEOUT=$(awk "BEGIN {print (${MAX_LATENCY} / 1000) + 1}")
LATENCY=$(curl -o /dev/null -s -w "%{time_total}" --max-time "$TIMEOUT" "$TEST_URL" 2>/dev/null)
LATENCY_MS=$(awk "BEGIN {print int($LATENCY * 1000)}" 2>/dev/null)
if [ -n "$LATENCY_MS" ] && [ "$LATENCY_MS" -lt "$MAX_LATENCY" ] && [ "$LATENCY_MS" -gt 0 ]; then exit 0; fi
log_msg "Internet down (${LATENCY_MS}ms), switching..."
for node in $(uci show passwall2 | grep "=nodes" | cut -d. -f2 | cut -d= -f1); do
    uci set passwall2.@global[0].node="$node"
    uci set passwall2.@global[0].default_node="$node" 2>/dev/null
    uci commit passwall2
    /etc/init.d/passwall2 restart
    sleep "$SLEEP"
    LATENCY=$(curl -o /dev/null -s -w "%{time_total}" --max-time "$TIMEOUT" "$TEST_URL" 2>/dev/null)
    LATENCY_MS=$(awk "BEGIN {print int($LATENCY * 1000)}" 2>/dev/null)
    if [ -n "$LATENCY_MS" ] && [ "$LATENCY_MS" -lt "$MAX_LATENCY" ] && [ "$LATENCY_MS" -gt 0 ]; then
        REMARK=$(uci -q get passwall2."$node".remarks 2>/dev/null)
        log_msg "Switched to $node ($REMARK) - ${LATENCY_MS}ms"
        exit 0
    fi
done
log_msg "All nodes failed!"
exit 1
SCRIPT
else
cat > /root/passwall-auto-switch.sh << 'SCRIPT'
#!/bin/sh
CONFIG="/root/passwall-bot.conf"
[ -f "$CONFIG" ] && . "$CONFIG"
MAX_LATENCY=${MAX_LATENCY:-1500}
SLEEP=10
LOCK_FILE="/tmp/passwall-auto-switch.lock"
TEST_URL="https://www.gstatic.com/generate_204"
LOG_FILE="/var/log/passwall-switch.log"
log_msg() { echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" | tee -a "$LOG_FILE"; logger -t internet-detector "$1"; }
if [ -f "$LOCK_FILE" ]; then exit 0; fi
touch "$LOCK_FILE"
trap "rm -f $LOCK_FILE" EXIT
CURRENT=$(uci -q get passwall.@global[0].tcp_node)
TIMEOUT=$(awk "BEGIN {print (${MAX_LATENCY} / 1000) + 1}")
LATENCY=$(curl -o /dev/null -s -w "%{time_total}" --max-time "$TIMEOUT" "$TEST_URL" 2>/dev/null)
LATENCY_MS=$(awk "BEGIN {print int($LATENCY * 1000)}" 2>/dev/null)
if [ -n "$LATENCY_MS" ] && [ "$LATENCY_MS" -lt "$MAX_LATENCY" ] && [ "$LATENCY_MS" -gt 0 ]; then exit 0; fi
log_msg "Internet down (${LATENCY_MS}ms), switching..."
for node in $(uci show passwall | grep "=nodes" | cut -d. -f2 | cut -d= -f1); do
    uci set passwall.@global[0].tcp_node="$node"
    uci commit passwall
    /etc/init.d/passwall restart
    sleep "$SLEEP"
    LATENCY=$(curl -o /dev/null -s -w "%{time_total}" --max-time "$TIMEOUT" "$TEST_URL" 2>/dev/null)
    LATENCY_MS=$(awk "BEGIN {print int($LATENCY * 1000)}" 2>/dev/null)
    if [ -n "$LATENCY_MS" ] && [ "$LATENCY_MS" -lt "$MAX_LATENCY" ] && [ "$LATENCY_MS" -gt 0 ]; then
        REMARK=$(uci -q get passwall."$node".remarks 2>/dev/null)
        log_msg "Switched to $node ($REMARK) - ${LATENCY_MS}ms"
        exit 0
    fi
done
log_msg "All nodes failed!"
exit 1
SCRIPT
fi
chmod +x /root/passwall-auto-switch.sh

# Telegram бот с кнопками
cat > /root/passwall-telegram-bot.sh << 'BOT'
#!/bin/sh
CONFIG="/root/passwall-bot.conf"
[ -f "$CONFIG" ] && . "$CONFIG"
LOG_FILE="/var/log/passwall-switch.log"

send_message() {
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" -d "text=$1" -d "parse_mode=HTML" > /dev/null 2>&1
}

get_keyboard() {
    echo '{"inline_keyboard":[[{"text":"📊 Status","callback_data":"status"},{"text":"📋 Log","callback_data":"log"}],[{"text":"🔄 Switch","callback_data":"switch"},{"text":"🔄 Restart","callback_data":"restart"}],[{"text":"📥 Update","callback_data":"update"},{"text":"⚙️ Settings","callback_data":"settings"}],[{"text":"❌ Hide","callback_data":"hide"}]]}'
}

get_settings_keyboard() {
    echo '{"inline_keyboard":[[{"text":"⏱️ 1 min","callback_data":"set_1"},{"text":"⏱️ 5 min","callback_data":"set_5"},{"text":"⏱️ 10 min","callback_data":"set_10"}],[{"text":"⏱️ 30 min","callback_data":"set_30"},{"text":"⏱️ Off","callback_data":"set_0"}],[{"text":"⚡ 800ms","callback_data":"lat_800"},{"text":"⚡ 1500ms","callback_data":"lat_1500"},{"text":"⚡ 3000ms","callback_data":"lat_3000"}],[{"text":"◀️ Back","callback_data":"back"}]]}'
}

check_status() {
BOT
if [ "$PW_VER" = "2" ]; then
echo '    current=$(uci -q get passwall2.@global[0].node 2>/dev/null)' >> /root/passwall-telegram-bot.sh
echo '    [ -z "$current" ] && current=$(uci -q get passwall2.@global[0].default_node)' >> /root/passwall-telegram-bot.sh
else
echo '    current=$(uci -q get passwall.@global[0].tcp_node)' >> /root/passwall-telegram-bot.sh
fi
cat >> /root/passwall-telegram-bot.sh << 'BOT'
    remark=$(uci -q get passwall."$current".remarks 2>/dev/null)
    latency=$(curl -o /dev/null -s -w "%{time_total}" --max-time 3 "https://www.gstatic.com/generate_204" 2>/dev/null)
    ms=$(awk "BEGIN {print int($latency * 1000)}" 2>/dev/null)
    if [ -n "$ms" ] && [ "$ms" -lt "${MAX_LATENCY:-1500}" ] && [ "$ms" -gt 0 ]; then
        send_message "✅ ONLINE\nServer: $current\n$remark\nPing: ${ms}ms\nCheck: ${CHECK_INTERVAL:-5} min" "$(get_keyboard)"
    else
        send_message "❌ OFFLINE\nServer: $current\n$remark\nPing: ${ms:-0}ms" "$(get_keyboard)"
    fi
}

show_settings() {
    send_message "⚙️ SETTINGS\n\nInterval: ${CHECK_INTERVAL:-5} min\nMax latency: ${MAX_LATENCY:-1500} ms" "$(get_settings_keyboard)"
}

send_log() {
    log_text=$(tail -20 "$LOG_FILE" 2>/dev/null | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
    [ -n "$log_text" ] && send_message "📋 LOG:\n$log_text" "$(get_keyboard)" || send_message "❌ Log empty" "$(get_keyboard)"
}

switch_node() {
    send_message "🔄 Switching..." ""
    /root/passwall-auto-switch.sh > /dev/null 2>&1
    sleep 2
    check_status
}

restart_passwall() {
    send_message "🔄 Restarting PassWall..." ""
    /etc/init.d/passwall restart
    sleep 3
    send_message "✅ PassWall restarted" "$(get_keyboard)"
    check_status
}

update_subscriptions() {
    send_message "🔄 Updating subscriptions..." ""
    lua /usr/share/passwall/subscribe.lua start 2>/dev/null
    sleep 5
    /etc/init.d/passwall restart
    sleep 3
    send_message "✅ Subscriptions updated" "$(get_keyboard)"
    check_status
}

set_interval() {
    sed -i "s/CHECK_INTERVAL=.*/CHECK_INTERVAL=$1/" /root/passwall-bot.conf
    sed -i '/passwall-auto-switch.sh/d' /etc/crontabs/root
    [ "$1" -gt 0 ] && echo "*/$1 * * * * /root/passwall-auto-switch.sh" >> /etc/crontabs/root
    /etc/init.d/cron restart
    CHECK_INTERVAL=$1
    send_message "✅ Interval set to $1 min" "$(get_keyboard)"
    show_settings
}

set_latency() {
    sed -i "s/MAX_LATENCY=.*/MAX_LATENCY=$1/" /root/passwall-bot.conf
    MAX_LATENCY=$1
    send_message "✅ Max latency set to ${1} ms" "$(get_keyboard)"
    show_settings
}

process_callback() {
    case "$1" in
        "status") check_status ;;
        "log") send_log ;;
        "switch") switch_node ;;
        "restart") restart_passwall ;;
        "update") update_subscriptions ;;
        "settings") show_settings ;;
        "back") show_settings ;;
        "set_0") set_interval 0 ;;
        "set_1") set_interval 1 ;;
        "set_5") set_interval 5 ;;
        "set_10") set_interval 10 ;;
        "set_30") set_interval 30 ;;
        "lat_800") set_latency 800 ;;
        "lat_1500") set_latency 1500 ;;
        "lat_3000") set_latency 3000 ;;
        "hide")
            curl -s "https://api.telegram.org/bot${BOT_TOKEN}/deleteMessage" -d "chat_id=${CHAT_ID}" -d "message_id=$2" > /dev/null 2>&1
            ;;
    esac
}

process_updates() {
    local last=0
    while true; do
        updates=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getUpdates?offset=$((last+1))&timeout=30")
        echo "$updates" | grep -q '"ok":true' || continue
        echo "$updates" | grep -E '("update_id"|"data"|"text")' | sed 's/},{/\n/g' | while IFS= read -r line; do
            uid=$(echo "$line" | grep -o '"update_id":[0-9]*' | cut -d: -f2)
            [ -n "$uid" ] && [ "$uid" -gt "$last" ] && last=$uid
            cb=$(echo "$line" | grep -o '"data":"[^"]*"' | cut -d'"' -f4)
            cid=$(echo "$line" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
            [ -n "$cb" ] && process_callback "$cb" "$cid"
            msg=$(echo "$line" | grep -o '"text":"[^"]*"' | cut -d'"' -f4)
            if [ -n "$msg" ]; then
                case "$msg" in
                    "/start"|"/status") check_status ;;
                    "/log") send_log ;;
                    "/switch") switch_node ;;
                    "/restart") restart_passwall ;;
                    "/update") update_subscriptions ;;
                    "/settings") show_settings ;;
                    "/help") send_message "Commands: /status, /log, /switch, /restart, /update, /settings" "$(get_keyboard)" ;;
                esac
            fi
        done
        sleep 2
    done
}

send_message "PassWall Bot Started\nCheck: ${CHECK_INTERVAL:-5} min\nLatency: ${MAX_LATENCY:-1500} ms\n\nCommands: /status, /log, /switch, /restart, /update, /settings" "$(get_keyboard)"
process_updates
BOT

chmod +x /root/passwall-telegram-bot.sh

# Настройка cron
. /root/passwall-bot.conf
CHECK_INTERVAL=${CHECK_INTERVAL:-5}
sed -i '/passwall-auto-switch.sh/d' /etc/crontabs/root 2>/dev/null
[ "$CHECK_INTERVAL" -gt 0 ] && echo "*/$CHECK_INTERVAL * * * * /root/passwall-auto-switch.sh" >> /etc/crontabs/root
/etc/init.d/cron restart

# Запуск бота
pkill -f "passwall-telegram-bot" 2>/dev/null
nohup /root/passwall-telegram-bot.sh > /dev/null 2>&1 &

touch /var/log/passwall-switch.log

echo ""
echo "========================================="
echo "✅ DONE! Send /status to your bot in Telegram"
echo "========================================="
