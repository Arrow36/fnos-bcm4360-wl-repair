# 工作原理

```mermaid
flowchart TD
    A["安装 FPK 或运行脚本"] --> B["检查架构、PCI ID、工具与内核头文件"]
    B --> C["校验或下载固定 SHA-256 的 Debian 驱动包"]
    C --> D["缓存 .deb 并恢复完整 /usr/src 源码"]
    D --> E["DKMS 为当前内核构建并安装 wl"]
    E --> F["写入冲突模块配置并加载 wl"]
    F --> G["启用 systemd 开机自愈"]
    G --> H{"fnOS 升级后 wl 是否存在？"}
    H -- 是 --> I["直接加载并退出"]
    H -- 否 --> J{"新内核头文件是否存在？"}
    J -- 是 --> D
    J -- 否 --> K["安全停止并记录明确错误"]
```

## 持久化位置

| 路径 | 用途 |
| --- | --- |
| `/var/lib/fnos-bcm4360-wl/` | 驱动包缓存及源码备份 |
| `/usr/src/broadcom-sta-6.30.223.271` | DKMS 源码 |
| `/usr/local/sbin/fnos-bcm4360-wl` | 持久安装脚本 |
| `/etc/systemd/system/fnos-bcm4360-wl.service` | 开机自愈服务 |
| `/etc/modprobe.d/fnos-bcm4360-wl.conf` | 冲突无线模块黑名单 |
| `/etc/modules-load.d/fnos-bcm4360-wl.conf` | `wl` 自动加载配置 |

FPK 应用卷中还保留脚本和离线驱动包。应用启动时若发现 systemd 入口被清理，会从应用卷重新执行完整安装，形成应用层与 systemd 层双重恢复。
