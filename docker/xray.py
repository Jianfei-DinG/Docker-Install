#!/usr/bin/env python3
# pip install watchdog
import os
import sys
import time
import signal
import subprocess
import logging
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
from threading import Timer

CONFIG_DIR = "./config"
LOG_FILE = "./config/logfile.log"
XRAY_EXEC = "./xray-x"
PID_FILE = "./xray.pid"
MAX_LOG_SIZE = 1 * 1024 * 1024  # 1MB
DEBOUNCE_DELAY = 1  # 秒

# 设置日志
logging.basicConfig(filename=LOG_FILE, level=logging.INFO,
                    format='%(asctime)s - %(message)s', datefmt='%Y-%m-%d %H:%M:%S')

# 确保日志目录存在
os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)

# 清理旧的 PID 文件
open(PID_FILE, 'w').close()

def rotate_log():
    if os.path.exists(LOG_FILE) and os.path.getsize(LOG_FILE) > MAX_LOG_SIZE:
        os.rename(LOG_FILE, f"{LOG_FILE}.old")
        open(LOG_FILE, 'w').close()
        logging.info("日志文件已轮转")

def cleanup(signum, frame):
    logging.info("正在清理并退出")
    with open(PID_FILE, 'r') as f:
        for line in f:
            pid, config = line.strip().split()
            try:
                os.kill(int(pid), signal.SIGTERM)
                logging.info(f"已停止 PID 为 {pid} 的 xray 进程，配置文件为 {config}")
            except ProcessLookupError:
                logging.info(f"PID {pid} 不存在")
    os.remove(PID_FILE)
    sys.exit(0)

signal.signal(signal.SIGINT, cleanup)
signal.signal(signal.SIGTERM, cleanup)

def start_xray(config_file):
    logging.info(f"正在启动 xray，配置文件为: {config_file}")
    
    # 等待文件稳定
    time.sleep(0.1)
    
    initial_size = os.path.getsize(config_file)
    time.sleep(1)
    new_size = os.path.getsize(config_file)
    
    if initial_size == new_size:
        process = subprocess.Popen([XRAY_EXEC, "-config", config_file],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        time.sleep(2)  # 等待进程启动
        
        if process.poll() is None:  # 检查进程是否仍在运行
            logging.info(f"xray 已成功启动，PID 为 {process.pid}，配置文件为 {config_file}")
            with open(PID_FILE, 'a') as f:
                f.write(f"{process.pid} {os.path.basename(config_file)}\n")
        else:
            logging.info(f"无法启动 xray，配置文件为 {config_file}")
    else:
        logging.info(f"文件 {config_file} 尚未完全写入")
    
    rotate_log()

def stop_xray(config_name):
    pids = []
    with open(PID_FILE, 'r') as f:
        for line in f:
            pid, conf = line.strip().split()
            if conf == config_name:
                pids.append(int(pid))
    
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
            logging.info(f"已停止 PID 为 {pid} 的 xray 进程，配置文件为 {config_name}")
        except ProcessLookupError:
            logging.info(f"PID 为 {pid} 的 xray 进程不存在，配置文件为 {config_name}")
    
    # 从 PID 文件中移除已停止的进程
    with open(PID_FILE, 'r') as f:
        lines = f.readlines()
    with open(PID_FILE, 'w') as f:
        f.writelines(line for line in lines if not line.strip().endswith(config_name))
    
    rotate_log()

def restart_xray(config_file):
    config_name = os.path.basename(config_file)
    stop_xray(config_name)
    start_xray(config_file)

class ConfigHandler(FileSystemEventHandler):
    def __init__(self):
        self.timers = {}
        self.file_created = set()

    def handle_event(self, event):
        if event.event_type == 'created' or (event.event_type == 'modified' and event.src_path in self.file_created):
            logging.info(f"检测到文件创建: {event.src_path}")
            self.file_created.discard(event.src_path)
            start_xray(event.src_path)
        elif event.event_type == 'modified':
            logging.info(f"检测到文件修改: {event.src_path}")
            restart_xray(event.src_path)
        elif event.event_type == 'deleted':
            logging.info(f"检测到文件删除: {event.src_path}")
            stop_xray(os.path.basename(event.src_path))

    def schedule_event(self, event):
        if event.src_path in self.timers:
            self.timers[event.src_path].cancel()
        
        self.timers[event.src_path] = Timer(DEBOUNCE_DELAY, self.handle_event, args=[event])
        self.timers[event.src_path].start()

    def on_created(self, event):
        if not event.is_directory and event.src_path.endswith('.json'):
            self.file_created.add(event.src_path)
            self.schedule_event(event)

    def on_deleted(self, event):
        if not event.is_directory and event.src_path.endswith('.json'):
            self.schedule_event(event)

    def on_modified(self, event):
        if not event.is_directory and event.src_path.endswith('.json'):
            self.schedule_event(event)

def main():
    logging.info("正在扫描目录中的配置文件...")
    for config_file in os.listdir(CONFIG_DIR):
        if config_file.endswith('.json'):
            full_path = os.path.join(CONFIG_DIR, config_file)
            logging.info(f"找到配置文件: {full_path}")
            with open(PID_FILE, 'r') as f:
                if not any(config_file in line for line in f):
                    start_xray(full_path)

    logging.info(f"正在监视 {CONFIG_DIR} 目录的变化...")
    event_handler = ConfigHandler()
    observer = Observer()
    observer.schedule(event_handler, CONFIG_DIR, recursive=False)
    observer.start()

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()
    observer.join()

if __name__ == "__main__":
    main()
