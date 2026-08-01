# 第三方软件声明

## Broadcom STA Wireless Driver

构建产物可包含以下未经修改的 Debian 软件包：

- 软件包：`broadcom-sta-dkms_6.30.223.271-30_amd64.deb`
- 上游版本：`6.30.223.271`
- Debian 修订版：`-30`
- SHA-256：`34917b5662cb03c453d28c834c229f20ace9fecd481c7bd9d8a789e1cc87fec5`
- 来源：[Debian 官方镜像](https://deb.debian.org/debian/pool/non-free/b/broadcom-sta/)
- Debian 分类：`non-free`

该包包含 Broadcom 的 proprietary binary object 以及 Debian 维护的构建文件和补丁。它不受本仓库 MIT License 约束。

Broadcom 条款仅允许完整、未经修改地分发其二进制软件，并仅用于匹配的 Broadcom 产品；分发时必须附带相应许可协议。构建器会从 `.deb` 中提取 `/usr/share/doc/broadcom-sta-dkms/copyright`，并将其作为 `THIRD_PARTY_LICENSES/broadcom-sta-dkms-copyright` 放入 FPK。

使用、复制或分发该驱动即表示接受其随附条款。若不接受，请仅使用本仓库源码，不要下载、构建或分发包含该驱动的 FPK。

参考：

- [Debian broadcom-sta 软件包](https://packages.debian.org/stable/kernel/broadcom-sta-dkms)
- [Debian Sources 中的 Broadcom 驱动源码包](https://sources.debian.org/src/broadcom-sta/)
