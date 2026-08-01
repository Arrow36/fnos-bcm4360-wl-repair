# 故障排查

## 先收集状态

```bash
sudo /usr/local/sbin/fnos-bcm4360-wl status
sudo systemctl status fnos-bcm4360-wl.service --no-pager
sudo journalctl -u fnos-bcm4360-wl.service -b --no-pager
lspci -nnk -d 14e4:43a0
```

## 缺少内核头文件

若日志提示以下路径不存在：

```text
/lib/modules/<当前内核>/build
```

必须先由 fnOS 提供或恢复与当前内核完全匹配的头文件。DKMS 无法在缺少头文件时生成模块。

## DKMS `Bad return status`

最后一行通常不是根因。查看脚本输出的日志位置，通常为：

```bash
sudo tail -n 100 /var/lib/dkms/broadcom-sta/6.30.223.271/build/make.log
```

未来大版本内核可能需要新的 Debian 修订补丁；不要在没有实际硬件验证的情况下只更新版本号或哈希。

## 模块存在但无法加载

```bash
modinfo -k "$(uname -r)" wl
sudo modprobe wl
sudo dmesg | tail -n 100
```

常见原因包括 Secure Boot、模块签名策略、ABI 不匹配或冲突模块仍在使用。脚本不会主动卸载 `b44`/`ssb`，因为它们可能承载有线 SSH。

## Wi-Fi 短暂断开

切换 `b43`、`brcmsmac`、`brcmfmac`、`bcma` 等冲突无线模块时，现有 Wi-Fi 可能中断。第一次安装应准备本机控制台或有线网络。
