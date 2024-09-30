import time
import subprocess
import sys
import logging
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

# 配置日志
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s', datefmt='%Y-%m-%d %H:%M:%S')

class NginxEventHandler(FileSystemEventHandler):
    def __init__(self):
        self.last_reload_time = 0
        self.reload_interval = 0.1  # 设置重载间隔为5秒

    def on_modified(self, event):
        if event.src_path.endswith('.conf'):
            current_time = time.time()
            if current_time - self.last_reload_time > self.reload_interval:
                logging.info(f'检测到 {event.src_path} 的变化，正在重载 Nginx...')
                result = subprocess.run(['nginx', '-s', 'reload'])
                if result.returncode == 0:
                    logging.info('Nginx 重载成功。')
                    self.last_reload_time = current_time
                else:
                    logging.error('Nginx 重载失败。')

    def on_created(self, event):
        logging.info(f'创建了配置文件: {event.src_path}')
        self.on_modified(event)

    def on_deleted(self, event):
        logging.info(f'删除了配置文件: {event.src_path}')
        self.on_modified(event)

def check_nginx_config():
    result = subprocess.run(['nginx', '-t'], capture_output=True, text=True)
    if result.returncode != 0:
        logging.error("Nginx 配置检查失败：")
        logging.error(result.stderr)
        sys.exit(1)
    logging.info("Nginx 配置检查通过。")

def start_nginx():
    subprocess.Popen(['nginx', '-g', 'daemon off;'])

if __name__ == "__main__":
    check_nginx_config()  # 检查配置
    start_nginx()         # 启动 Nginx

    paths = ["/etc/nginx/http.d", "/etc/nginx/stream.d"]
    event_handler = NginxEventHandler()
    observer = Observer()

    for path in paths:
        observer.schedule(event_handler, path, recursive=False)

    observer.start()
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()
    observer.join()
