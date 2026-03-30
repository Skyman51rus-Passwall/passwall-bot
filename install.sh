#!/bin/sh

echo ""
echo "========================================="
echo "  🤖 PassWall + Telegram Bot Installer"
echo "  github.com/Skyman51rus-Passwall/passwall-bot"
echo "========================================="
echo ""

# Проверка наличия PassWall
PW1_INSTALLED=$(ls /etc/init.d/passwall 2>/dev/null)
PW2_INSTALLED=$(ls /etc/init.d/passwall2 2>/dev/null)

if [ -z "$PW1_INSTALLED" ] && [ -z "$PW2_INSTALLED" ]; then
    echo "⚠️  PassWall не обнаружен"
    echo ""
    echo "Выбери действие:"
    echo "   1 - Установить PassWall 1"
    echo "   2 - Установить PassWall 2"
    echo "   0 - Пропустить"
    printf "Выбери 1, 2 или 0: "
    read INSTALL_PW
    
    case "$INSTALL_PW" in
        1)
            echo ""
            echo "Установка PassWall 1..."
            rm -f /tmp/passwall.sh
            wget -q https://raw.githubusercontent.com/amirhosseinchoghaei/Passwall/main/passwall.sh -O /tmp/passwall.sh
            chmod 777 /tmp/passwall.sh
            sh /tmp/passwall.sh
            ;;
        2)
            echo ""
            echo "Установка PassWall 2..."
            rm -f /tmp/passwall2x.sh
            wget -q https://raw.githubusercontent.com/amirhosseinchoghaei/Passwall/main/passwall2x.sh -O /tmp/passwall2x.sh
            chmod 777 /tmp/passwall2x.sh
            sh /tmp/passwall2x.sh
            ;;
        0)
            echo "Пропускаем установку PassWall"
            ;;
        *)
            echo "Неверный выбор, пропускаем установку PassWall"
            ;;
    esac
    echo ""
fi

echo ""
echo "========================================="
echo "  Telegram Bot Setup"
echo "========================================="
echo ""

echo "1. Открой Telegram, найди @BotFather"
echo "2. Отправь команду /newbot"
echo "3. Введи имя бота, например MyRouterBot"
echo "4. Введи username, должно заканчиваться на _bot"
echo "5. Скопируй полученный токен"
echo ""
printf "Введи токен бота: "
read BOT_TOKEN

echo ""
echo "1. Найди @userinfobot в Telegram"
echo "2. Отправь ему команду /start"
echo "3. Скопируй свой ID цифрами"
echo ""
printf "Введи свой Chat ID: "
read CHAT_ID

echo ""
echo "Выбери версию PassWall для бота:"
echo "   1 - PassWall 1"
echo "   2 - PassWall 2"
printf "Выбери 1 или 2: "
read PW_VER

echo ""
echo "Настройки мониторинга:"
printf "Интервал проверки в минутах (по умолч 5): "
read CHECK_INT
[ -z "$CHECK_INT" ] && CHECK_INT=5
printf "Максимальная задержка в мс (по умолч 1500): "
read MAX_LAT
[ -z "$MAX_LAT" ] && MAX_LAT=1500

echo ""
echo "Установка бота..."

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
    local text="$1"
    local keyboard="$2"
    if [ -n "$keyboard" ]; then
        curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
            -d "chat_id=${CHAT_ID}" -d "text=${text}" -d "parse_mode=HTML" \
            -d "reply_markup=$keyboard" > /dev/null 2>&1
    else
        curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
            -d "chat_id=${CHAT_ID}" -d "text=${text}" -d "parse_mode=HTML" > /dev/null 2>&1
    fi
}

get_keyboard() {
    cat << 'KB'
{"inline_keyboard":[[{"text":"📊 Статус","callback_data":"status"},{"text":"📋 Лог","callback_data":"log"}],[{"text":"🔄 Переключить","callback_data":"switch"},{"text":"🔄 Перезапуск","callback_data":"restart"}],[{"text":"📥 Обновить","callback_data":"update"},{"text":"⚙️ Настройки","callback_data":"settings"}],[{"text":"❌ Скрыть","callback_data":"hide"}]]}
KB
}

get_settings_keyboard() {
    cat << 'KB'
{"inline_keyboard":[[{"text":"⏱️ 1 мин","callback_data":"set_1"},{"text":"⏱️ 5 мин","callback_data":"set_5"},{"text":"⏱️ 10 мин","callback_data":"set_10"}],[{"text":"⏱️ 30 мин","callback_data":"set_30"},{"text":"⏱️ Откл","callback_data":"set_0"}],[{"text":"⚡ 800ms","callback_data":"lat_800"},{"text":"⚡ 1500ms","callback_data":"lat_1500"},{"text":"⚡ 3000ms","callback_data":"lat_3000"}],[{"text":"◀️ Назад","callback_data":"back"}]]}
KB
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
    interval=${CHECK_INTERVAL:-5}
    if [ -n "$ms" ] && [ "$ms" -lt "${MAX_LATENCY:-1500}" ] && [ "$ms" -gt 0 ]; then
        send_message "✅ ONLINE\nСервер: $current\n$remark\nПинг: ${ms}ms\nПроверка: каждые $interval мин" "$(get_keyboard)"
    else
        send_message "❌ OFFLINE\nСервер: $current\n$remark\nПинг: ${ms:-0}ms" "$(get_keyboard)"
    fi
}

show_settings() {
    send_message "⚙️ НАСТРОЙКИ\n\n⏱️ Интервал: ${CHECK_INTERVAL:-5} мин\n⚡ Задержка: ${MAX_LATENCY:-1500} мс\n\nНажми кнопку для изменения:" "$(get_settings_keyboard)"
}

send_log() {
    log_text=$(tail -20 "$LOG_FILE" 2>/dev/null | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
    [ -n "$log_text" ] && send_message "📋 ПОСЛЕДНИЙ ЛОГ:\n<code>$log_text</code>" "$(get_keyboard)" || send_message "❌ Лог пуст" "$(get_keyboard)"
}

switch_node() {
    send_message "🔄 Переключение..." ""
    /root/passwall-auto-switch.sh > /dev/null 2>&1
    sleep 2
    check_status
}

restart_passwall() {
    send_message "🔄 Перезапуск PassWall..." ""
    /etc/init.d/passwall restart
    sleep 3
    send_message "✅ PassWall перезапущен" "$(get_keyboard)"
    check_status
}

update_subscriptions() {
    send_message "🔄 Обновление подписок..." ""
    lua /usr/share/passwall/subscribe.lua start 2>/dev/null
    sleep 5
    /etc/init.d/passwall restart
    sleep 3
    send_message "✅ Подписки обновлены" "$(get_keyboard)"
    check_status
}

set_interval() {
    sed -i "s/CHECK_INTERVAL=.*/CHECK_INTERVAL=$1/" /root/passwall-bot.conf
    sed -i '/passwall-auto-switch.sh/d' /etc/crontabs/root
    [ "$1" -gt 0 ] && echo "*/$1 * * * * /root/passwall-auto-switch.sh" >> /etc/crontabs/root
    /etc/init.d/cron restart
    CHECK_INTERVAL=$1
    send_message "✅ Интервал изменен на $1 минут" "$(get_keyboard)"
    show_settings
}

set_latency() {
    sed -i "s/MAX_LATENCY=.*/MAX_LATENCY=$1/" /root/passwall-bot.conf
    MAX_LATENCY=$1
    send_message "✅ Задержка изменена на ${1} мс" "$(get_keyboard)"
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
                    "/help") send_message "🤖 КОМАНДЫ БОТА:\n/status - статус\n/log - лог\n/switch - переключить\n/restart - перезапуск\n/update - обновить\n/settings - настройки\n\nТакже есть КНОПКИ под сообщениями!" "$(get_keyboard)" ;;
                esac
            fi
        done
        sleep 2
    done
}

send_message "🤖 PassWall БОТ ЗАПУЩЕН!\n\n✅ Проверка: ${CHECK_INTERVAL:-5} мин\n⚡ Задержка: ${MAX_LATENCY:-1500} мс\n\n📌 КОМАНДЫ:\n/status - статус\n/log - лог\n/switch - переключить\n/restart - перезапуск\n/update - обновить\n/settings - настройки\n\n👇 Нажми на кнопки под этим сообщением!" "$(get_keyboard)"
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

# Автозапуск
if ! grep -q "passwall-telegram-bot.sh" /etc/rc.local 2>/dev/null; then
    sed -i '/exit 0/d' /etc/rc.local 2>/dev/null
    echo "nohup /root/passwall-telegram-bot.sh > /dev/null 2>&1 &" >> /etc/rc.local
    echo "exit 0" >> /etc/rc.local
    chmod +x /etc/rc.local
fi

touch /var/log/passwall-switch.log

echo ""
echo "========================================="
echo "✅ УСТАНОВКА ЗАВЕРШЕНА!"
echo "========================================="
echo ""
echo "📱 Открой Telegram и отправь боту: /status"
echo "🔘 Под сообщением появятся КНОПКИ"
echo ""
echo "Твои настройки:"
if [ "$PW_VER" = "2" ]; then
    echo "   Версия для бота: PassWall 2"
else
    echo "   Версия для бота: PassWall 1"
fi
echo "   Интервал: $CHECK_INTERVAL мин"
echo "   Задержка: $MAX_LAT мс"
echo ""
echo "📋 Лог: tail -f /var/log/passwall-switch.log"
echo "========================================="
