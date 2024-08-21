#!/bin/bash

CONFIG_DIR="./config"  # 配置目录路径
LOG_FILE="./config/logfile.log"  # 日志文件路径
XRAY_EXEC="./xray"  # xray 可执行文件路径
PID_FILE="./xray.pid"  # PID 文件路径
MAX_LOG_SIZE=$((10 * 1024 * 1024))  # 最大日志大小 (10MB)
DEBOUNCE_DELAY=10  # 去抖动时间（秒）

# 确保日志目录存在
mkdir -p "$(dirname "$LOG_FILE")"

# 清理旧的 PID 文件
> "$PID_FILE"

# 日志轮转函数
rotate_log() {
    if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE") -gt $MAX_LOG_SIZE ]; then
        mv "$LOG_FILE" "${LOG_FILE}.old"
        touch "$LOG_FILE"
        echo "$(date) - 日志文件已轮转" >> "$LOG_FILE"
    fi
}

# 信号处理函数
cleanup() {
    echo "$(date) - 清理并退出" >> "$LOG_FILE"
    while read -r pid config; do
        if ps -p "$pid" > /dev/null; then
            kill "$pid" 2>/dev/null
            echo "$(date) - 已停止 PID 是 $pid 的 xray 进程, 配置文件为 $config" >> "$LOG_FILE"
        else
            echo "$(date) - PID $pid 不存在" >> "$LOG_FILE"
        fi
    done < "$PID_FILE"
    rm -f "$PID_FILE"
    exit 0
}

# 设置信号处理
trap cleanup SIGINT SIGTERM

# 函数：启动 xray 进程
start_xray() {
    local config_file="$1"
    echo "$(date) - 正在启动 xray, 配置文件为: $config_file" >> $LOG_FILE

    # 等待文件稳定
    sleep 0.1  # 等待 5 秒

    # 检查文件是否稳定
    local initial_size=$(stat -c%s "$config_file")
    sleep 1
    local new_size=$(stat -c%s "$config_file")

    if [ "$initial_size" -eq "$new_size" ]; then
        $XRAY_EXEC -config "$config_file" >> $LOG_FILE 2>&1 &
        local pid=$!
        sleep 2  # 等待进程启动
        if pgrep -f "$XRAY_EXEC -config $config_file" > /dev/null; then
            echo "$(date) - xray 已成功启动, PID 为 $pid 配置文件为 $config_file" >> $LOG_FILE
            echo "$pid $(basename "$config_file")" >> "$PID_FILE"
        else
            echo "$(date) - 无法启动 xray, 配置文件为 $config_file" >> $LOG_FILE
        fi
    else
        echo "$(date) - 文件 $config_file 尚未完全写入" >> $LOG_FILE
    fi

    rotate_log
}

# 函数：停止 xray 进程
stop_xray() {
    local config_name="$1"
    local pids=$(grep " $config_name" "$PID_FILE" | awk '{print $1}')
    if [ -n "$pids" ]; then
        for pid in $pids; do
            if ps -p $pid > /dev/null; then
                echo "$(date) - 正在停止 PID 为 $pid 的 xray 进程, 配置文件为 $config_name" >> $LOG_FILE
                kill "$pid" 2>/dev/null
                if [ $? -eq 0 ]; then
                    echo "$(date) - xray 已成功停止, PID 为 $pid, 配置文件为 $config_name" >> $LOG_FILE
                else
                    echo "$(date) - 无法停止 PID 为 $pid 的 xray 进程, 配置文件为 $config_name" >> $LOG_FILE
                fi
            else
                echo "$(date) - PID 为 $pid 的 xray 进程不存在, 配置文件为 $config_name" >> $LOG_FILE
            fi
        done
        sed -i "/ $config_name/d" "$PID_FILE"
    else
        echo "$(date) - 未找到正在运行的 xray 进程, 配置文件为 $config_name" >> $LOG_FILE
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
echo "$(date) - 正在扫描目录中的配置文件..." >> $LOG_FILE
for config_file in "$CONFIG_DIR"/*.json; do
    if [ -f "$config_file" ]; then
        echo "$(date) - 找到配置文件: $config_file" >> $LOG_FILE
        if ! grep -q "$(basename "$config_file")" "$PID_FILE"; then
            start_xray "$config_file"
        fi
    fi
done

# 监控目录变化
echo "$(date) - 正在监视 $CONFIG_DIR 目录的变化..." >> $LOG_FILE
inotifywait -m -e create,delete,modify --format '%w%f %e' "$CONFIG_DIR" | while read file event; do
    if [[ "$file" == *.json && "$file" != "$LOG_FILE" ]]; then  # 排除日志文件
        # 使用去抖动机制处理文件修改事件
        sleep $DEBOUNCE_DELAY
        echo "$(date) - 检测到 $event 事件发生在 $file" >> $LOG_FILE
        if [[ "$event" == "CREATE" ]]; then
            echo "$(date) - 检测到文件创建: $file" >> $LOG_FILE
            if ! grep -q "$(basename "$file")" "$PID_FILE"; then
                start_xray "$file"
            else
                echo "$(date) - xray 已经在运行 $file" >> $LOG_FILE
            fi
        elif [[ "$event" == "DELETE" ]]; then
            echo "$(date) - 检测到文件删除: $file" >> $LOG_FILE
            stop_xray "$(basename "$file")"
        elif [[ "$event" == "MODIFY" ]]; then
            echo "$(date) - 检测到文件修改: $file" >> $LOG_FILE
            restart_xray "$file"
        fi
    fi
    rotate_log
done
