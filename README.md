# PictureSearch

一款隐私优先的原生 macOS 图片搜索应用，通过自然语言在 Apple Photos 图库中查找截图和照片。

PictureSearch 使用 PhotoKit 只读访问图库，在本机完成 Apple Vision OCR、索引和搜索。当前 MVP 支持根据图片中的文字、拍摄时间和图片类型进行组合检索，并为每条结果提供可解释的命中原因。

> 项目仍处于原型开发阶段。请参阅下方的[当前状态](#当前状态)与[已知限制](#已知限制)。

## 核心能力

- 使用自然语言搜索 Photos 中的截图和照片
- 识别中文、英文及中英文混排的图片文字
- 理解“最近”“去年夏天”“2025 年 10 月”等时间线索
- 识别“截图”“照片”“文档图”等基础图片类型
- 融合 OCR、时间和类型信号进行排序
- 展示置信度与结构化命中原因
- 在本机 SQLite 中持久化索引和任务状态
- 支持失败重试和清除本地派生索引
- 为本地图文向量模型提供安全接入、验证与降级机制

## 隐私原则

- 仅通过 PhotoKit 访问 Photos 资产
- 默认只读，不修改、删除、移动或整理用户照片
- 图片、OCR 文本、向量和索引默认只在本机处理
- 不实现人物识别或人脸聚类
- 不在模型未验证时返回伪视觉语义结果
- 清除索引只删除本地派生数据，不影响 Photos 原图

## 搜索示例

```text
包含 Hermes 的截图
去年夏天的照片
2025 年 10 月的截图
文档里包含发票号码的图片
```

查询解析器会把自然语言拆分为 OCR、时间和类型信号。OCR 精确命中优先，多信号同时匹配的结果会获得更高置信度；只有时间或类型等弱信号时，结果会明确标记为“相近结果”。

## 技术架构

| 模块 | 技术 |
|---|---|
| 用户界面 | SwiftUI |
| 图库访问 | PhotoKit |
| 文字识别 | Apple Vision |
| 本地索引 | SQLite |
| 查询解析与排序 | Swift 本地规则与多信号融合 |
| 视觉语义扩展 | Core ML 图文双塔模型适配层 |
| 自动测试 | XCTest |

```text
Apple Photos
    │
    ▼
PhotoKit 只读访问
    │
    ├── 缩略图与元数据
    └── OCR 图片请求
            │
            ▼
      Apple Vision OCR
            │
            ▼
       SQLite 本地索引
            │
            ▼
   查询解析与多信号融合排序
            │
            ▼
     可解释的搜索结果
```

## 当前状态

| 里程碑 | 状态 |
|---|---|
| PhotoKit 授权与真实图库读取 | 已实现 |
| SQLite 本地索引与任务状态 | 已实现 |
| Apple Vision OCR 管线 | 已实现 |
| 视觉模型接入骨架、验证门禁和安全降级 | 已实现 |
| OCR、时间、类型检索与融合排序 | 已实现 |
| 完整结果网格、大图预览与图片复用 | 待开发 |
| 增量更新、异常恢复与重建 | 待开发 |
| 真实查询评测与最终验收 | 待完成 |

当前路线优先完成 OCR、时间和类型搜索的 MVP 闭环。真实 CLIP 类视觉语义搜索属于后续增强能力，只有模型来源、许可证、tokenizer、预处理和真实 Photos 样本验证全部通过后才会启用。

## 系统要求

- macOS
- Xcode（建议使用完整 Xcode，而非仅安装 Command Line Tools）
- 用户授权访问 Photos 图库

项目目前未承诺 App Store 分发、所有 macOS 版本兼容性或超大规模图库性能。

## 快速开始

克隆仓库：

```bash
git clone git@github.com:Chunting-H/Picture-search.git
cd Picture-search
```

使用 Xcode 打开：

```bash
open PictureSearch.xcodeproj
```

选择 `PictureSearch` scheme 和 `My Mac`，完成本地签名配置后运行。

首次启动时，应用会说明图库用途并请求 Photos 权限。授权后可选择近一周、近一个月、近一年或全部图库范围，然后建立本地索引并执行 OCR。

## 构建与测试

命令行构建：

```bash
xcodebuild \
  -project PictureSearch.xcodeproj \
  -scheme PictureSearch \
  -destination 'platform=macOS' \
  build
```

运行测试：

```bash
xcodebuild \
  -project PictureSearch.xcodeproj \
  -scheme PictureSearch \
  -destination 'platform=macOS' \
  test
```

当前代码已通过正式 Xcode build，并通过 61 个 XCTest。Photos 权限、真实图库 OCR 效果和搜索体验仍需在 Xcode 图形环境中人工复验。

## 可选的视觉语义模型

仓库不包含也不会自动下载真实 Core ML 图文模型。应用在未安装模型时仍可使用 OCR、时间和类型搜索。

视觉模型包需要放在应用沙盒的 Application Support 目录中：

```text
PictureSearch/EmbeddingModelPackage/
├── EmbeddingModelManifest.json
├── CLIPImageEncoder.mlmodelc
├── CLIPTextEncoder.mlmodelc
└── tokenizer resources
```

模型启用前会检查：

- 来源、许可证和模型版本
- 文件大小与 SHA-256
- Core ML 输入输出名称、shape 和数据类型
- tokenizer 与起止 token 配置
- 图片预处理参数
- 真实 Photos 样本的中英文语义验证结果

详细流程参阅：

- [模型接入与验证指南](docs/模型接入与验证指南.md)
- [视觉模型候选评估](docs/视觉模型候选评估.md)

## 项目结构

```text
PictureSearch/
├── App/             # 应用入口与状态管理
├── Features/        # 授权、图库、索引和搜索界面
├── Models/          # 图库、索引、OCR 与搜索模型
├── Resources/       # 模型 manifest 示例
└── Services/        # PhotoKit、OCR、索引、搜索和 embedding

PictureSearchTests/  # XCTest
docs/               # 开发、决策、验收和模型文档
AGENTS.md            # 项目级开发约束
PLAN.md              # 里程碑计划
```

## 已知限制

- 尚未完成完整结果网格、大图预览、复制或拖拽复用
- 真实图库上的 OCR 准确率仍需更完整的样本验收
- 搜索目前使用本地记录扫描和轻量字符串匹配，尚未使用 SQLite FTS
- “海边夕阳”等纯画面查询需要通过验证的视觉模型
- 大图库下的索引性能、内存峰值和持续运行稳定性尚未完成生产级验证
- iCloud 图片能否读取取决于系统 Photos 状态和网络可用性

更多信息参阅[已知问题](docs/已知问题.md)。

## 开发文档

- [开发计划](PLAN.md)
- [开发记录](docs/开发记录.md)
- [决策记录](docs/决策记录.md)
- [验收记录](docs/验收记录.md)
- [已知问题](docs/已知问题.md)

## Roadmap

- [ ] 完整搜索结果网格和命中说明
- [ ] 大图预览及复制或拖拽复用
- [ ] 手动增量刷新、失败恢复和清除后重建
- [ ] 至少 20 条真实查询评测
- [ ] 真实视觉模型接入与中英文效果验证
- [ ] 大规模图库性能和稳定性优化

## License

项目尚未添加开源许可证。在许可证明确前，仓库内容默认保留所有权利。
