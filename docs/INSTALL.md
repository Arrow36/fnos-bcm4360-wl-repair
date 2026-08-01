# 安装指南

## 安装前检查

目标设备必须满足：

```bash
uname -m
lspci -Dn | grep -i '14e4:43a0'
test -e "/lib/modules/$(uname -r)/build" && echo headers-ok
```

架构应为 `x86_64` 或 `amd64`，PCI 检查应找到 BCM4360，内核头文件链接必须存在。系统还需要 `dkms`、`dpkg-deb`、`lspci`、`modinfo`、`modprobe` 和 `sha256sum`。

## FPK 安装

1. 从 Releases 下载 FPK 与 `SHA256SUMS.txt`。
2. 在可信设备上校验 FPK，或手工对照 SHA-256：

   ```bash
   grep 'fnos-bcm4360-wl-repair_1.0.0_x86_64.fpk$' SHA256SUMS.txt | sha256sum -c -
   ```
3. 打开 fnOS「应用中心」，选择「手动安装」。
4. 上传 FPK，并确认第三方应用和 root 权限提示。

FPK 内置经校验的 Debian 驱动包，不需要目标设备联网。

## 脚本安装

```bash
chmod +x fnos-bcm4360-oneclick.sh
sudo ./fnos-bcm4360-oneclick.sh install
```

脚本会从 Debian 官方镜像下载固定驱动版本，验证 SHA-256 后才继续。

### 离线模式

将以下 Debian 包和脚本一同上传：

```text
https://deb.debian.org/debian/pool/non-free/b/broadcom-sta/broadcom-sta-dkms_6.30.223.271-30_amd64.deb
```

然后运行：

```bash
sudo ./fnos-bcm4360-oneclick.sh install \
  --deb ./broadcom-sta-dkms_6.30.223.271-30_amd64.deb
```

要求的驱动包 SHA-256：

```text
34917b5662cb03c453d28c834c229f20ace9fecd481c7bd9d8a789e1cc87fec5
```

## 卸载行为

卸载 FPK 会禁用并移除自动维护服务和 `/usr/local/sbin/fnos-bcm4360-wl`，但不会立刻移除当前已编译模块、modprobe 配置或离线缓存，以避免正在使用 Wi-Fi 的设备瞬间断网。

若确实需要彻底清理，请先切换到本机控制台或有线网络，再根据实际系统状态手工处理；不要在仅靠该 Wi-Fi 连接的 SSH 会话中操作。
