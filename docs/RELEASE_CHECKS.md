# v1.5.0 本地发布检查

日期：2026-09-19。以下是本地构建记录，不代表已经发布到 GitHub。

| 检查 | 结果 |
| --- | --- |
| Swift Debug 构建 | 通过 |
| arm64 Release 构建 | 通过 |
| x86_64 Release 交叉构建 | 通过；尚未在 Intel Mac 实机运行 |
| Universal 合并及两种架构检查 | 通过 |
| 应用临时签名完整性 | 通过；不是 Developer ID 签名或公证 |
| 应用图标 | 已生成并查看 PNG，ICNS 转换通过 |
| DMG 创建、校验、只读挂载 | 通过 |
| DMG 内 Applications 快捷入口、应用签名、帮助文件 | 通过 |
| ZIP 完整性与 DMG/ZIP 的 SHA-256 | 通过 |
| 安装文档的本地链接 | 通过 |
| GitHub 工作流及 Issue 表单 YAML 语法 | 通过；尚未在 GitHub runner 运行 |
| 首次安装后的完整权限流程、登录自启动 | 此公开包尚未重新实测 |
| Developer ID 签名、Apple 公证 | 未进行：没有可用的 Developer ID Application 证书 |
| GitHub 上传 | 待仓库地址与 GitHub 身份验证 |

之前本地版本已验证基本翻译、编辑和窗口布局，但本表只对本次实际完成的发布检查作出声明。发布前若补做实机检查，应更新此记录。
