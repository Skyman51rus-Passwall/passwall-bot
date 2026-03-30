#!/bin/sh

echo "========================================="
echo "  PassWall Bot Installer"
echo "========================================="
echo ""

printf "Токен бота (от @BotFather): "
read BOT_TOKEN

printf "Chat ID (от @userinfobot): "
read CHAT_ID

echo ""
echo "Выбери версию PassWall:"
echo "1 - PassWall 1"
echo "2 - PassWall 2"
printf "1 или 2: "
read PW_VER

printf "Интервал проверки (мин, по умолч 5): "
read CHECK_INT
[ -z "$CHECK_INT" ] && CHECK_INT=5

printf "Макс. задержка (мс, по умолч 1500): "
read MAX_LAT
[ -z "$MAX_LAT" ] && MAX_LAT=1500

echo ""
echo "Установка..."

cat > /root/passwall-bot.conf << CFG
CHECK_INTERVAL=$CHECK_INT
MAX_LATENCY=$MAX_LAT
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
CFG

if [ "$PW_VER" = "2" ]; then
    echo "Установка для PassWall 2..."
    
    cat > /root/passwall-auto-switch.sh << 'SCRIPT'
#!/bin/sh
CONFIG="/root/passwall-bot.conf"
[ -f "$CONFIG" ] && . "$CONFIG"
MAX_LATENCY=${MAX_LATENCY:-1500}
SLEEP=10
LOCK_FILE="/tmp/passwall-auto-switch.lock"
TEST_URL="https://www.gstatic.com/generate_204"
LOG_FILE="/var/log/passwall-switch.log"

log_msg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" | tee -a "$LOG_FILE"
    logger -t internet-detector "$1"
}

if [ -f "$LOCK_FILE" ]; then exit 0; fi
touch "$LOCK_FILE"
trap "rm -f $LOCK_FILE" EXIT

CURRENT=$(uci -q get passwall2.@global[0].node)
[ -z "$CURRENT" ] && CURRENT=$(uci -q get passwall2.@global[0].default_node)

TIMEOUT=$(awk "BEGIN {print (${MAX_LATENCY} / 1000) + 1}")
LATENCY=$(curl -o /dev/null -s -w "%{time_total}" --max-time "$TIMEOUT" "$TEST_URL" 2>/dev/null)
LATENCY_MS=$(awk "BEGIN {print int($LATENCY * 1000)}" 2>/dev/null)

if [ -n "$LATENCY_MS" ] && [ "$LATENCY_MS" -lt "$MAX_LATENCY" ] && [ "$LATENCY_MS" -gt 0 ]; then
    exit 0
fi

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
    chmod +x /root/passwall-auto-switch.sh

else
    echo "Установка для PassWall 1..."
    
    cat > /root/passwall-auto-switch.sh << 'SCRIPT'
#!/bin/sh
CONFIG="/root/passwall-bot.conf"
[ -f "$CONFIG" ] && . "$CONFIG"
MAX_LATENCY=${MAX_LATENCY:-1500}
SLEEP=10
LOCK_FILE="/tmp/passwall-auto-switch.lock"
TEST_URL="https://www.gstatic.com/generate_204"
LOG_FILE="/var/log/passwall-switch.log"

log_msg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" | tee -a "$LOG_FILE"
    logger -t internet-detector "$1"
}

if [ -f "$LOCK_FILE" ]; then exit 0; fi
touch "$LOCK_FILE"
trap "rm -f $LOCK_FILE" EXIT

CURRENT=$(uci -q get passwall.@global[0].tcp_node)

TIMEOUT=$(awk "BEGIN {print (${MAX_LATENCY} / 1000) + 1}")
LATENCY=$(curl -o /dev/null -s -w "%{time_total}" --max-time "$TIMEOUT" "$TEST_URL" 2>/dev/null)
LATENCY_MS=$(awk "BEGIN {print int($LATENCY * 1000)}" 2>/dev/null)

if [ -n "$LATENCY_MS" ] && [ "$LATENCY_MS" -lt "$MAX_LATENCY" ] && [ "$LATENCY_MS" -gt 0 ]; then
    exit 0
fi

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
    chmod +x /root/passwall-auto-switch.sh
fi

# Telegram бот
cat > /root/passwall-telegram-bot.sh << 'BOTSCRIPT'
#!/bin/sh
CONFIG="/root/passwall-bot.conf"
[ -f "$CONFIG" ] && . "$CONFIG"
LOG_FILE="/var/log/passwall-switch.log"

send_message() {
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "text=$1" \
        -d "parse_mode=HTML" > /dev/null 2>&1
}

check_status() {
BOTSCRIPT

if [ "$PW_VER" = "2" ]; then
    cat >> /root/passwall-telegram-bot.sh << 'BOTSCRIPT'
    current=$(uci -q get passwall2.@global[0].node 2>/dev/null)
    [ -z "$current" ] && current=$(uci -q get passwall2.@global[0].default_node)
BOTSCRIPT
else
    cat >> /root/passwall-telegram-bot.sh << 'BOTSCRIPT'
    current=$(uci -q get passwall.@global[0].tcp_node)
BOTSCRIPT
fi

cat >> /root/passwall-telegram-bot.sh << 'BOTSCRIPT'
    remark=$(uci -q get passwall."$current".remarks 2>/dev/null)
    latency=$(curl -o /dev/null -s -w "%{time_total}" --max-time 3 "https://www.gstatic.com/generate_204" 2>/dev/null)
    ms=$(awk "BEGIN {print int($latency * 1000)}" 2>/dev/null)
    
    if [ -n "$ms" ] && [ "$ms" -lt "${MAX_LATENCY:-1500}" ] && [ "$ms" -gt 0 ]; then
        send_message "✅ ONLINE\nСервер: ${current}\n${remark}\nПинг: ${ms}ms\nПроверка: ${CHECK_INTERVAL:-5} мин"
    else
        send_message "❌ OFFLINE\nСервер: ${current}\n${remark}\nПинг: ${ms:-0}ms"
    fi
}

case "$1" in
    status) check_status ;;
    log) send_message "📋 Лог:\n$(tail -20 "$LOG_FILE" 2>/dev/null)" ;;
    switch) /root/passwall-auto-switch.sh; sleep 2; check_status ;;
    restart) 
BOTSCRIPT

if [ "$PW_VER" = "2" ]; then
    echo "        /etc/init.d/passwall2 restart" >> /root/passwall-telegram-bot.sh
else
    echo "        /etc/init.d/passwall restart" >> /root/passwall-telegram-bot.sh
fi

cat >> /root/passwall-telegram-bot.sh << 'BOTSCRIPT'
        sleep 3
        check_status
        ;;
    update) 
        send_message "🔄 Обновление..."
        lua /usr/share/passwall/subscribe.lua start 2>/dev/null
BOTSCRIPT

if [ "$PW_VER" = "2" ]; then
    echo "        /etc/init.d/passwall2 restart" >> /root/passwall-telegram-bot.sh
else
    echo "        /etc/init.d/passwall restart" >> /root/passwall-telegram-bot.sh
fi

cat >> /root/passwall-telegram-bot.sh << 'BOTSCRIPT'
        sleep 3
        check_status
        ;;
    *) echo "Команды: status, log, switch, restart, update" ;;
esac
BOTSCRIPT

chmod +x /root/passwall-telegram-bot.sh

# Скрипт настроек
cat > /root/passwall-settings.sh << 'SETTINGS'
#!/bin/sh
CONFIG="/root/passwall-bot.conf"
. "$CONFIG"

case "$1" in
    interval)
        if [ -n "$2" ] && [ "$2" -ge 0 ] && [ "$2" -le 60 ]; then
            sed -i "s/CHECK_INTERVAL=.*/CHECK_INTERVAL=$2/" "$CONFIG"
            sed -i '/passwall-auto-switch.sh/d' /etc/crontabs/root 2>/dev/null
            [ "$2" -gt 0 ] && echo "*/$2 * * * * /root/passwall-auto-switch.sh" >> /etc/crontabs/root
            /etc/init.d/cron restart
            echo "✅ Интервал изменен на $2 минут"
        fi
        ;;
    latency)
        if [ -n "$2" ] && [ "$2" -ge 100 ] && [ "$2" -le 5000 ]; then
            sed -i "s/MAX_LATENCY=.*/MAX_LATENCY=$2/" "$CONFIG"
            echo "✅ Задержка изменена на ${2}ms"
        fi
        ;;
    status)
        echo "Интервал: ${CHECK_INTERVAL:-5} мин, Задержка: ${MAX_LATENCY:-1500} мс"
        ;;
    *)
        echo "Команды: interval [0-60], latency [100-5000], status"
        ;;
esac
SETTINGS
chmod +x /root/passwall-settings.sh

# Настройка cron
. /root/passwall-bot.conf
CHECK_INTERVAL=${CHECK_INTERVAL:-5}
sed -i '/passwall-auto-switch.sh/d' /etc/crontabs/root 2>/dev/null
[ "$CHECK_INTERVAL" -gt 0 ] && echo "*/$CHECK_INTERVAL * * * * /root/passwall-auto-switch.sh" >> /etc/crontabs/root
/etc/init.d/cron restart

touch /var/log/passwall-switch.log

echo ""
echo "========================================="
echo "✅ УСТАНОВКА ЗАВЕРШЕНА!"
echo "========================================="
echo ""
echo "📱 В Telegram отправь боту: /status"
echo ""
