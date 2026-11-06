# 在线游戏市场设计

资源仓库 `zeelinkCN/game-bench-library` 是独立游戏市场，平台通过 `store.json`
读取合集，通过 `catalog.json` 读取单款游戏、封面和 SHA-256。

## 安装流程

1. 浏览线上封面、搜索游戏或选择合集。
2. 下载所选 ROM 和封面，不下载未选择内容。
3. 校验 ROM 的 SHA-256 与目录一致。
4. 保存到 `~/Library/Application Support/GameBench/ROMs`。
5. 平台的收藏、存档和金手指继续保存在本机。

当前开发期资源仓库保持 Private。未来改为 Public 后，客户端可直接使用 GitHub
Raw URL，不需要在应用中保存 Token。若继续保持 Private，则需增加 GitHub OAuth
Device Flow，并将访问凭据放进 Keychain，不能把个人 Token 写进源码或应用包。

tvOS 版本可复用同一市场协议，但下载资源要遵守 Apple TV 的磁盘空间和按需清理策略。
