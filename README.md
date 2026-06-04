# container.sh 快速备忘

## 日常用法（本机）

```bash
./container.sh build                              # 构建镜像（只需一次）
./container.sh run                                # 启动容器（默认全部 GPU）
docker exec -it isaaclab232_$(whoami) bash        # 进入容器（默认 ~/project）
```

- 镜像名：`sim51_lab232_<用户名>`
- 容器名：`isaaclab232_<用户名>`
- 项目目录：在**你执行 `run` 时所在的目录**挂载到 `~/project`
- Isaac Lab 安装在 `~/IsaacLab`（镜像内）
- 项目依赖需自行在挂载目录执行 `./install_project.sh`（进容器后手动一次即可）

---

## 指定 GPU / 容器名

```bash
./container.sh run                              # 默认容器名 isaaclab232_<用户名>
./container.sh run --name isaaclab232_hz_exp1   # 自定义容器名（多实例时用）
./container.sh run --gpu 1                      # 只用 GPU 1
./container.sh run --name isaaclab232_hz_gpu0 --gpu 0
```

`--name` 与 `--gpu` 顺序可互换；不指定 `--name` 时用默认 `isaaclab232_<用户名>`。

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
Dockerfile 构建时会把本机 `whoami` / `id -u` / `id -g` 传入镜像并创建对应的运行用户。为了保持极速构建并极大减小镜像层体积（避免 `chown -R` 触发 Docker OverlayFS 的文件拷贝），`/isaac-sim` 整体对运行用户保持只读，仅在构建的最后对运行时必须写入的三个缓存/日志子目录（`kit/cache`、`kit/data`、`kit/logs`）执行细粒度的 `chown`。  
只有 **build** 可覆盖，用于给 HPC 等其它 UID 提前构建镜像：


```bash
# 先在目标机器上 id，再把 uid/gid 填进来
CONTAINER_USER=hwang721 \
CONTAINER_UID=204491 \
CONTAINER_GID=201375 \
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