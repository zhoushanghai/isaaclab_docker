# container.sh 快速备忘

## 日常用法（本机）

```bash
./container.sh build                              # 构建镜像（只需一次）
./container.sh run                                # 启动容器（默认全部 GPU）
docker exec -it isaaclab232_$(whoami) bash        # 进入容器
```

- 镜像名：`sim51_lab232_<用户名>`
- 容器名：`isaaclab232_<用户名>`
- 项目目录挂载到容器内 `/workspace/project`
- 首次进入 shell 会自动安装本项目（`install_project.sh`）

---

## 指定 GPU

```bash
./container.sh run              # 全部 GPU
./container.sh run --gpu 1        # 只用 GPU 1
./container.sh run --gpu 0,1      # 用 GPU 0 和 1
```

---

## 查看用户信息

`container.sh` 是 bash 脚本，查用户信息建议用 bash（fish 终端也适用）：

```bash
bash -c 'echo "user=$(whoami) uid=$(id -u) gid=$(id -g) display=${DISPLAY:-未设置}"'
```

示例输出：

```text
user=hz uid=1001 gid=1001 display=localhost:10.0
```

---

## SSH X11 转发（远程弹 GUI 窗口）

本机需有 X Server（Linux 桌面 / macOS XQuartz / Windows VcXsrv）。

`~/.ssh/config` 示例：

```text
Host 5090
    HostName <服务器IP>
    User hz
    ForwardX11 yes
    ForwardX11Trusted yes
```

连接后确认：

```bash
bash -c 'echo $DISPLAY'    # 应有值，如 localhost:10.0
```

然后 `./container.sh run` 即可；容器内跑仿真时去掉 `--headless` 才能看到窗口。

---

## build 时指定用户（可选）

**run 固定用本机当前用户**，不受下列变量影响。  
Dockerfile 中 `--install` 固定用占位用户 **hz:1001**（便于 Docker 缓存）；`container.sh build` 会把本机 `whoami` / `id -u` / `id -g` 传入最后一层：运行用户对齐本机 UID，**加入 isaac_sim(1001) 组读 `/isaac-sim`**，只对 `/home` + `/workspace` chown（快，且不碰挂载的 project）。  
只有 **build** 可覆盖，用于给 HPC 等其它 UID 提前构建镜像（`--install` 走缓存，仅最后一层 usermod + chown）：

```bash
# 先在目标机器上 id，再把 uid/gid 填进来
CONTAINER_USER=hz \
CONTAINER_UID=100523 \
CONTAINER_GID=100523 \
./container.sh build
```

本机开发直接 `./container.sh build` 即可，默认用 `whoami` / `id -u` / `id -g`。

---

## 可选 build 环境变量

| 变量 | 作用 | 默认 |
|------|------|------|
| `CONTAINER_USER` / `UID` / `GID` | build 时写入镜像的用户 | 本机用户 |
| `ISAACLAB_REPO` | Isaac Lab 仓库 | 官方 GitHub |
| `ISAACLAB_COMMIT` | 分支 / tag / commit | 见 `container.sh` |


```
docker save sim51_lab232_hwang721:latest | pv | gzip > /home/hz/docker_images/sim51_lab232_hwang721.tar.gz
```