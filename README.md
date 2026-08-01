# fnOS BCM4360 / BCM94360CS2 驱动自愈工具

[![Validate](https://github.com/Arrow36/fnos-bcm4360-wl-repair/actions/workflows/validate.yml/badge.svg)](https://github.com/Arrow36/fnos-bcm4360-wl-repair/actions/workflows/validate.yml)
[![GitHub release](https://img.shields.io/github/v/release/Arrow36/fnos-bcm4360-wl-repair)](https://github.com/Arrow36/fnos-bcm4360-wl-repair/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

为 x86_64 飞牛 fnOS 自动安装并维护 Broadcom BCM4360 `wl` 驱动，适用于 Apple BCM94360CS2 等 PCI ID 为 `14e4:43a0` 的网卡。

> [!WARNING]
> 本工具需要 root 权限，会编译并加载内核模块、写入 `/etc` 并启用 systemd 服务。第一次安装建议使用有线网络或本机终端操作。请勿用于不匹配的硬件。

## 功能

- 安装前检查架构、PCI ID、`cfg80211`、DKMS 工具和当前内核头文件。
- 固定使用 Debian `broadcom-sta-dkms 6.30.223.271-30`，并验证 SHA-256。
- 缓存未经修改的驱动包，在 fnOS 更新覆盖源码后自动恢复。
- 为当前内核编译、安装并加载 `wl`。
- 通过 `fnos-bcm4360-wl.service` 在内核升级后自动重新编译。
- 同时保留 FPK 应用层恢复入口，防止系统升级清理 systemd 文件。
- 不主动卸载或屏蔽可能承载有线网络的 `b44`、`ssb`。

## 安装

### 方式一：fnOS 应用中心（推荐）

1. 从 [Releases](https://github.com/Arrow36/fnos-bcm4360-wl-repair/releases/latest) 下载 `fnos-bcm4360-wl-repair_1.0.0_x86_64.fpk` 和 `SHA256SUMS.txt`。
2. 校验 SHA-256。
3. 在 fnOS「应用中心 → 手动安装」中上传 FPK。
4. 确认第三方应用及 root 权限提示后安装。

FPK 已包含固定版本驱动包，目标设备安装时不需要联网。

### 方式二：SSH 一键脚本

下载 Release 中的 `fnos-bcm4360-oneclick.sh`，不要直接把远程脚本通过管道交给 shell：

```bash
chmod +x fnos-bcm4360-oneclick.sh
sudo ./fnos-bcm4360-oneclick.sh
```

脚本首次安装会从 Debian 下载驱动包；也可通过 `--deb` 指定提前下载的离线包。完整说明见[安装指南](docs/INSTALL.md)。

## 兼容范围

| 项目 | 要求 |
| --- | --- |
| 操作系统 | x86_64/amd64 飞牛 fnOS |
| 硬件 | Broadcom BCM4360 / Apple BCM94360CS2 |
| PCI ID | `14e4:43a0` |
| 内核 | 必须存在 `/lib/modules/$(uname -r)/build` |
| 驱动 | `broadcom-sta-dkms 6.30.223.271-30` |

Secure Boot、内核模块签名策略或未来的大版本内核变化仍可能阻止 `wl` 加载。遇到问题请先查看[故障排查](docs/TROUBLESHOOTING.md)。

## 常用命令

```bash
# 只读状态检查
sudo /usr/local/sbin/fnos-bcm4360-wl status

# 修复当前内核
sudo /usr/local/sbin/fnos-bcm4360-wl repair

# 强制重新编译
sudo /usr/local/sbin/fnos-bcm4360-wl repair --force

# 查看开机自愈日志
sudo journalctl -u fnos-bcm4360-wl.service -b --no-pager
```

## 从源码构建

构建器只使用 Python 标准库。若 `.cache/` 中没有固定驱动包，会从 Debian 官方镜像下载并校验：

```bash
python scripts/build_fpk.py
python scripts/verify_fpk.py
```

也可以明确提供已下载的包：

```bash
python scripts/build_fpk.py --driver /path/to/broadcom-sta-dkms_6.30.223.271-30_amd64.deb
```

产物写入 `dist/`。构建使用固定归档时间和所有者信息，相同输入应得到相同的 FPK 哈希。详见[发布流程](docs/RELEASING.md)。

## 仓库结构

```text
src/                    一键安装与自愈脚本
packaging/fpk/          fnOS FPK 元数据和生命周期脚本
scripts/                可复现构建与完整性校验工具
docs/                   安装、架构、排障和发布文档
.github/workflows/      自动构建与验证
```

## 许可证与免责声明

本仓库原创代码采用 [MIT License](LICENSE)。构建出的 FPK 包含 Broadcom 的非自由混合驱动，该驱动不受 MIT License 约束；其 Debian/Broadcom 许可文本会随 FPK 一并提供。详情见[第三方声明](THIRD_PARTY_NOTICES.md)。

本项目与飞牛 fnOS、Broadcom、Apple 或 Debian 均无隶属或官方支持关系。内核模块操作具有断网和系统不稳定风险，请自行评估并准备可回退的本机访问方式。
