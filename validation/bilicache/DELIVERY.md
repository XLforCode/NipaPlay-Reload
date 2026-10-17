# BiliCache 测试交付（2026-10-17）

代码分别管理；播放器 `origin` 为 `XLforCode/NipaPlay-Reload`，官方为 `upstream`。播放器运行时源码提交 `1ad9a308f1a38a2fa5ae63ded9a891de766482bd`，扩展 1.7.0 对应 `b043bcb2b78265f05e9cc97d59bd1033dc915800`；协议版本 1。原始设计初稿未修改。

## 本地可用文件

| 文件（仓库相对路径） | SHA-256 |
| --- | --- |
| `build/bilicache-release/NipaPlay-Windows-x64-bilicache.zip` | `5b7c6f7bb491c49ea82906102b4bd377de23c56e55a1a3dfa2b8a029526c6e5f` |
| `build/bilicache-final-artifacts/bilicache-bridge-Windows-X64/bilicache-bridge-Windows-X64.zip` | `c4cb8375c82bc970d13869b3e61545a19aaf76dcf71a46afafd0b644538d515c` |
| `build/bilicache-final-artifacts/bilicache-bridge-macOS-ARM64/bilicache-bridge-macOS-ARM64.tar.gz` | `0ec437c43cbfa33460f21b2311c7d6cd26e15ff0aafc58a952399174f667a610` |
| `build/bilicache-final-artifacts/bilicache-bridge-macOS-X64/bilicache-bridge-macOS-X64.tar.gz` | `69c263b0d7837e478ed5b6e912b29ecc7473f7cf24e933c167b9fe7cc28a36fe` |

扩展仓库 `artifacts/bilibili-downloader-1.7.0.zip`：`498a72abe602ff640355a2507aea266803a617b04f5735107f544a0536b772b1`。

Windows ZIP 的逐文件哈希位于 `build/bilicache-release/SHA256.json`，实际程序位于 `build/bilicache-release/validated/NipaPlay/NipaPlay.exe`。桥接组件来自提交 `359dfe09fd87201a62b5a57930856a86a9e2d01e`，后续播放器修复未修改桥接实现。安装说明见 `tools/bilicache_bridge/README.md`。

## 验证范围

- 扩展 Node 175/175、隔离真实 Chrome 旧入口 12/12、缓存 5/5；包一致性 27 文件通过。
- 桥接三平台各 12 项 Dart 测试通过；Windows 编译后二进制消息及中文路径启动通过。
- 播放器相关 Flutter 测试 16/16；静态分析无 error，原有 warning/info 保留在日志。Windows Release 构建成功。
- Windows 实际 GUI 已验证冷/热启动、三类弹幕、拖动、空 XML 和连续打开，详细证据在扩展仓库 `validation/BILICACHE_ACCEPTANCE.md`。

## 尚待验收

[原构建](https://github.com/XLforCode/NipaPlay-Reload/actions/runs/39009849077) 的 macOS libmpv 依赖准备已成功缓存，随后停止旧应用打包，让[运行时修复版](https://github.com/XLforCode/NipaPlay-Reload/actions/runs/39011067681) 复用依赖缓存。任何旧提交包不能代替最终修复版。macOS 测试包保持沙盒，临时签名，未公证。

真实 Chrome 目录授权/重启恢复、用户安装登记和配对，以及 macOS GUI、书签恢复、权限撤销均未实机验收。不能据此宣布双平台首版完成。
