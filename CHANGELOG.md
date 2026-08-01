# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 的组织方式。

## [1.0.0] - 2026-07-29

### Added

- 针对 BCM4360（PCI ID `14e4:43a0`）的安装、状态检查和修复命令。
- 固定哈希的 Debian `broadcom-sta-dkms 6.30.223.271-30` 下载与离线缓存。
- DKMS 源码恢复、当前内核构建和 `wl` 加载。
- systemd 开机自愈服务与 FPK 应用层双重恢复。
- 可复现 FPK 构建、结构/哈希/许可证校验和 GitHub Actions。

[1.0.0]: https://github.com/Arrow36/fnos-bcm4360-wl-repair/releases/tag/v1.0.0
