# 参与贡献

感谢你帮助改进 fnOS BCM4360 驱动自愈工具。

## 提交问题

请说明 fnOS 版本、`uname -r`、网卡 PCI ID、安装方式，以及以下命令的脱敏输出：

```bash
sudo /usr/local/sbin/fnos-bcm4360-wl status
sudo systemctl status fnos-bcm4360-wl.service --no-pager
sudo journalctl -u fnos-bcm4360-wl.service -b --no-pager
```

不要提交密码、令牌、SSH 私钥、完整公网 IP、主机名或其他隐私信息。

## 本地检查

```bash
bash -n src/fnos-bcm4360-oneclick.sh
python scripts/build_fpk.py --driver /path/to/broadcom-sta-dkms_6.30.223.271-30_amd64.deb
python scripts/verify_fpk.py
```

生命周期脚本必须使用 LF 换行和 `#!/bin/bash`。修改驱动版本时，必须同步更新 URL、SHA-256、文档和测试，并说明实际 fnOS 硬件验证结果。

## Pull Request

- 每个 PR 聚焦一个问题。
- 清楚说明风险、测试环境和回退方式。
- 不要提交 `.deb`、`.fpk`、ZIP、缓存或其他生成物。
