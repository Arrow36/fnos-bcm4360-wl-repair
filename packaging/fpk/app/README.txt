BCM4360 网卡驱动修复应用

目标硬件：Broadcom BCM4360，PCI ID 14e4:43a0
目标系统：x86_64 飞牛 fnOS

本应用内置经过 SHA-256 校验的 broadcom-sta-dkms 驱动包。
安装时会为当前内核编译并加载 wl 模块，同时安装开机自愈服务。
fnOS 升级并重启后，自愈服务会检查新内核并在需要时自动重新编译。
如果升级清理了系统盘上的服务文件，应用自身启动时还会从应用卷内恢复服务。

项目主页：https://github.com/Arrow36/fnos-bcm4360-wl-repair

内置驱动属于非自由第三方软件，不受本项目 MIT License 约束。
完整 Debian/Broadcom 版权与许可文本位于：
THIRD_PARTY_LICENSES/broadcom-sta-dkms-copyright

内核模块编译依赖当前内核对应的头文件：
/lib/modules/$(uname -r)/build
