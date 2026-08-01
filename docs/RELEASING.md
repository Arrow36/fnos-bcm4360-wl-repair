# 发布流程

1. 更新 `VERSION`、FPK `manifest`、README 和 `CHANGELOG.md`。
2. 使用固定驱动包完成两次构建，并确认 FPK SHA-256 相同。
3. 运行：

   ```bash
   bash -n src/fnos-bcm4360-oneclick.sh
   python scripts/build_fpk.py
   python scripts/verify_fpk.py
   ```

4. 在实际 x86_64 fnOS + BCM4360 设备上验证首次安装、重启、状态检查及模拟内核升级后的自愈。
5. 创建 `v<版本>` Git tag 和 GitHub Release。
6. 上传 `dist/` 中的 FPK、一键脚本和 `SHA256SUMS.txt`。

Release 说明必须提示 root/内核模块风险、目标 PCI ID、内核头文件要求，以及 Broadcom 驱动的 non-free 许可证边界。
