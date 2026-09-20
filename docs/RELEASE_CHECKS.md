# v1.0.0 本地发布检查

日期：2026-09-20。以下是重新打包后的本地构建记录。

| 检查 | 结果 |
| --- | --- |
| `SelectionTranslate --self-check` | 通过 |
| Universal 合并及两种架构检查 | 通过：`x86_64 arm64` |
| 应用临时签名完整性 | 通过；不是 Developer ID 签名或公证 |
| Info.plist 版本 | `CFBundleShortVersionString` 1.0.0，`CFBundleVersion` 1；无 `LSUIElement` |
| DMG 创建、`hdiutil verify`、只读挂载 | 通过 |
| DMG 内 Applications 快捷入口、应用签名、安装说明、帮助文件 | 通过 |
| ZIP 完整性与 DMG/ZIP 的 SHA-256 | 通过 |
| 安装文档的本地链接 | 通过 |
| GitHub 工作流及 Issue 表单 YAML 语法 | 已存在于仓库；本次未在 GitHub runner 重新运行 |
| 首次安装后的完整权限流程、登录自启动 | 此公开包尚未重新实测 |
| Developer ID 签名、Apple 公证 | 未进行：没有可用的 Developer ID Application 证书 |

之前本地版本已验证基本翻译、编辑和窗口布局，但本表只对本次实际完成的发布检查作出声明。
