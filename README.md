# Condense（浓缩阅读）

内容聚合阅读 App：从 Safari / 微信 / 钉钉 / 飞书等通过系统分享面板把网页链接或文档（PDF / DOCX）分享进来，App 提取正文并精美排版。阅读页底部有一条「压缩 bar」，手指向上推，文章内容随手势被逐级压缩（全文 → 章节要点 → 段落摘要 → 三句话 → 一句话中心思想），松手停在该级别。

本地优先，无后端。摘要引擎使用 iOS 26 Foundation Models 框架，不可用时自动降级为截断式简易摘要。

## 构建前提

- macOS + **Xcode 26**（iOS 26 SDK，含 Foundation Models 框架）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)：`brew install xcodegen`
- 一台支持 Apple Intelligence 的设备（模拟器或无 Apple Intelligence 的设备会自动走降级摘要）
- 开发者账号需要在主 App 与 Share Extension 两个 target 上启用 App Group：`group.com.condense.app.shared`

## 生成工程并构建

```bash
cd Condense
xcodegen generate          # 生成 Condense.xcodeproj
open Condense.xcodeproj    # 在 Xcode 中打开，选择签名团队后运行
```

SwiftSoup 为唯一第三方依赖，通过 SwiftPM 在首次打开工程时自动拉取。

## 项目结构

```
Condense/
├── project.yml                  # XcodeGen 工程定义（两个 target + Info.plist inline）
├── Condense/                    # 主 App（bundle id: com.condense.app）
│   ├── CondenseApp.swift        # @main 入口，SwiftData 容器，前台时拉取共享收件箱
│   ├── Models/
│   │   ├── Article.swift        # 文章模型（段落、图片、来源、摘要关系）
│   │   └── SummaryLevel.swift   # 压缩级别 0-4 的摘要模型
│   ├── Services/
│   │   ├── ContentPipeline.swift    # 统一入口 ingest，按类型分发 + 触发摘要
│   │   ├── WebArticleExtractor.swift # 网页正文提取（SwiftSoup，Readability 风格）
│   │   ├── DocumentExtractor.swift   # PDF（PDFKit）/ DOCX（内置极简 ZIP + XMLParser）
│   │   ├── SummarizerService.swift   # Foundation Models 摘要，含降级 fallback
│   │   └── SharedInbox.swift         # App Group 收件箱（与 Extension 共享编译）
│   ├── Views/
│   │   ├── LibraryView.swift    # 文章库列表（搜索 / 归档 / 粘贴导入）
│   │   ├── ReaderView.swift     # 阅读页（衬线排版、图文混排）
│   │   ├── CompressBar.swift    # 底部压缩 bar（上推手势切换压缩级别）
│   │   └── Components/LevelIndicator.swift
│   ├── Assets.xcassets/         # AppIcon 占位 + AccentColor
│   └── Condense.entitlements    # App Group
└── CondenseShare/               # Share Extension（com.condense.app.share）
    ├── ShareViewController.swift    # 静默写入收件箱后 completeRequest
    └── CondenseShare.entitlements  # App Group
```

## 数据流

1. Share Extension 收到分享 → 把内容 / 文件写入 App Group 容器的 `inbox/` 目录（manifest JSON + 文件副本）。
2. 主 App 启动或回到前台 → `ContentPipeline.pullSharedInbox()` 拉取并逐条 `ingest`。
3. `ingest` 按类型分发：URL → `WebArticleExtractor`，文件 → `DocumentExtractor`，文本 → 直接分段。
4. 存入 SwiftData 后，后台触发 `SummarizerService` 预生成 1-4 级摘要。
5. 阅读页 `CompressBar` 上推手势在 0-4 级间连续切换，松手吸附。
