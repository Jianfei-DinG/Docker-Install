import time
import subprocess
import sys
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

class NginxEventHandler(FileSystemEventHandler):
    def on_modified(self, event):
        if event.src_path.endswith('.conf'):
            print(f'检测到 {event.src_path} 的变化，正在重载 Nginx...')
            result = subprocess.run(['nginx', '-s', 'reload'])
            if result.returncode == 0:
                print('Nginx 重载成功。')
            else:
                print('Nginx 重载失败。')

    def on_created(self, event):
        print(f'创建了配置文件: {event.src_path}')
        self.on_modified(event)

    def on_deleted(self, event):
        print(f'删除了配置文件: {event.src_path}')
        self.on_modified(event)


def check_nginx_config():
    # 检查 Nginx 配置文件的有效性
    result = subprocess.run(['nginx', '-t'], capture_output=True, text=True)
    if result.returncode != 0:
        print("Nginx 配置检查失败：")
        print(result.stderr)
        sys.exit(1)
    print("Nginx 配置检查通过。")

def start_nginx():
    # 启动 Nginx
    subprocess.Popen(['nginx', '-g', 'daemon off;'])

if __name__ == "__main__":
    check_nginx_config()  # 检查配置
    start_nginx()         # 启动 Nginx

    # 监控的目录
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
