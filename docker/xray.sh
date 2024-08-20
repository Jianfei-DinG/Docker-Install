#!/bin/bash

CONFIG_DIR="./config"  # 配置目录路径
LOG_FILE="./config/logfile.log"  # 日志文件路径
XRAY_EXEC="./xray"  # xray 可执行文件路径
PID_FILE="./xray.pid"  # PID 文件路径
MAX_LOG_SIZE=$((10 * 1024 * 1024))  # 最大日志大小 (10MB)

# 确保日志目录存在
mkdir -p "$(dirname "$LOG_FILE")"

# 清理旧的 PID 文件
> "$PID_FILE"

# 日志轮转函数
rotate_log() {
    if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE") -gt $MAX_LOG_SIZE ]; then
        mv "$LOG_FILE" "${LOG_FILE}.old"
        touch "$LOG_FILE"
        echo "$(date) - Log file rotated" >> "$LOG_FILE"
    fi
}

# 信号处理函数
cleanup() {
    echo "$(date) - Cleaning up and exiting" >> "$LOG_FILE"
    while read -r pid config; do
        kill "$pid" 2>/dev/null
        echo "$(date) - Stopped xray process with PID $pid for $config" >> "$LOG_FILE"
    done < "$PID_FILE"
    rm -f "$PID_FILE"
    exit 0
}

# 设置信号处理
trap cleanup SIGINT SIGTERM

# 函数：启动 xray 进程
start_xray() {
    local config_file="$1"
    echo "$(date) - Starting xray with config: $config_file" >> $LOG_FILE
    $XRAY_EXEC -config "$config_file" >> $LOG_FILE 2>&1 &
    local pid=$!
    sleep 2  # 等待进程启动
    if ps -p $pid > /dev/null; then
        echo "$(date) - xray started successfully with PID $pid for $config_file" >> $LOG_FILE
        echo "$pid $(basename "$config_file")" >> "$PID_FILE"
    else
        echo "$(date) - Failed to start xray for $config_file" >> $LOG_FILE
    fi
    rotate_log
}

# 函数：停止 xray 进程
stop_xray() {
    local config_name="$1"
    local pid=$(grep " $config_name" "$PID_FILE" | awk '{print $1}')
    if [ -n "$pid" ]; then
        echo "$(date) - Stopping xray with PID $pid for $config_name" >> $LOG_FILE
        kill "$pid"
        if [ $? -eq 0 ]; then
            echo "$(date) - xray stopped successfully with PID $pid for $config_name" >> $LOG_FILE
            sed -i "/ $config_name/d" "$PID_FILE"
        else
            echo "$(date) - Failed to stop xray with PID $pid for $config_name" >> $LOG_FILE
        fi
    else
        echo "$(date) - No running xray process found for $config_name" >> $LOG_FILE
    fi
    rotate_log
}

# 函数：重新启动 xray 进程
restart_xray() {
    local config_file="$1"
    local config_name="$(basename "$config_file")"
    stop_xray "$config_name"
    start_xray "$config_file"
}

# 扫描目录中的现有配置文件并启动 xray
echo "$(date) - Scanning directory for existing config files..." >> $LOG_FILE
for config_file in "$CONFIG_DIR"/*.json; do
    if [ -f "$config_file" ]; then
        echo "$(date) - Found config file: $config_file" >> $LOG_FILE
        if ! grep -q "$(basename "$config_file")" "$PID_FILE"; then
            start_xray "$config_file"
        fi
    fi
done

# 监控目录变化
echo "$(date) - Monitoring $CONFIG_DIR for changes..." >> $LOG_FILE
inotifywait -m -e create,delete,modify --format '%w%f %e' "$CONFIG_DIR" | while read file event; do
    if [[ "$file" == *.json ]]; then
        echo "$(date) - Detected $event on $file" >> $LOG_FILE
        if [[ "$event" == "CREATE" ]]; then
            echo "$(date) - Detected file creation: $file" >> $LOG_FILE
            if ! grep -q "$(basename "$file")" "$PID_FILE"; then
                start_xray "$file"
            else
                echo "$(date) - xray is already running for $file" >> $LOG_FILE
            fi
        elif [[ "$event" == "DELETE" ]]; then
            echo "$(date) - Detected file deletion: $file" >> $LOG_FILE
            stop_xray "$(basename "$file")"
        elif [[ "$event" == "MODIFY" ]]; then
            echo "$(date) - Detected file modification: $file" >> $LOG_FILE
            restart_xray "$file"
        fi
    fi
    rotate_log
done