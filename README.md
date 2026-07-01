<<<<<<< HEAD
# PictureSearch

PictureSearch 是一个原生 macOS App，用于通过自然语言搜索用户的 Photos 图库。

项目计划通过 PhotoKit 读取 Photos 资产，在本机建立 OCR 和图片语义索引，并返回带有清晰命中说明的搜索结果。

## 当前状态

当前已完成第 1、2、3、4、5 个里程碑的代码实现：App 会说明用途和隐私原则，申请 Photos 权限，并在授权后按近一周、近一个月、近一年或全部范围读取图片缩略图与创建时间；读取到的资产摘要会写入本机 SQLite 索引；用户可以在索引状态区启动 Apple Vision OCR，将识别文本、任务状态、失败类型和单张耗时写入本地索引；本地搜索面板可以基于 OCR 文本、时间和类型信号返回带命中原因和置信度的搜索结果。

当前 MVP 路线已经收敛为：先交付本地 OCR 图片搜索、时间/类型解析、基础融合排序、结果解释、大图预览、复用入口、手动刷新、失败重试和清除重建。真实 CLIP 类视觉语义搜索延期为增强能力，只有在合法模型、匹配 tokenizer、预处理配置、真实 Photos 样本验证和中英文效果验证全部通过后才启用；在此之前不会返回伪视觉结果。

当前已接入本机 OCR 管线和 MVP 搜索管线：查询解析器支持“最近”“去年”“去年夏天”“2025 年 10 月”等时间表达，支持“截图”“照片”“文档图”等基础类型线索，并可按 OCR 文本做关键词检索；融合排序会优先 OCR 精确命中，多信号同时匹配高于单一弱信号，并为每条结果生成结构化命中原因。纯画面语义查询在真实视觉模型未验证前会明确降级，不会返回伪视觉结果。视觉语义搜索方面已实现本地模型适配层、模型 manifest 解析、manifest 模板资源、运行时 manifest 自动加载入口、Application Support 本机模型包加载入口、manifest 缺失或模板占位诊断、模型文件大小元数据校验、模型和 tokenizer SHA-256 校验、结构化模型资源打包清单、打包资源实际大小与哈希审计、可复制的 manifest 建议字段、本地模型包预检报告、候选 `.mlmodelc` Core ML 加载、运行时模型就绪 Core ML 加载检查、输入输出接口检查、输入 shape 与数据类型校验、研究/评估/非商业许可证限制校验、图片编码器 Core ML 推理骨架、文本编码器 Core ML 推理骨架、后台 utility 推理执行策略、图片预处理、本地 JSON BPE tokenizer 适配层、文本 token 输入构造、tokenizer 起止 token ID 与 manifest 比对、真实 Photos 验证样本描述符、样本描述 JSON 文档解析和隐私安全审计、App bundle 样本描述自动读取、模型与样本描述预检报告、App 内技术验证预检状态展示、当前模型版本技术验证门禁、App 内运行技术验证按钮、App 内视觉查询验证入口、PhotoKit 样本加载桥接、技术验证结果状态展示、技术验证 Markdown 报告本机保存、向量持久化、模型版本记录、当前模型版本下旧向量需重建状态、模型资源就绪诊断、交互式视觉索引批量上限、余弦相似度检索测试、真实模型接入后的技术验证入口、包含模型接入清单、就绪诊断、相似度差距和单样本推理耗时的 Markdown 验证报告输出，以及中文模型接入与验证指南和视觉模型候选评估，但尚未内置真实 Core ML CLIP 模型，也尚未验证 tokenizer 与真实文本编码器完全匹配。真实图库 OCR 准确率和搜索体验仍需在 Xcode 中人工验收；视觉语义模型效果、平均耗时和样本覆盖移到增强阶段验收。当前仍未实现大图预览。

当前界面采用更紧凑的左侧状态栏和右侧照片工作区：授权说明、本地索引和 OCR 摘要集中在左侧；OCR 操作、视觉索引诊断和重试按钮默认折叠到详情区，避免长期挤占照片浏览空间。照片网格占据右侧主要区域，顶部保留读取范围切换和重新读取按钮；每张缩略图把创建时间和基础尺寸信息叠放在图片底部，并使用更紧凑的网格列宽和行距，便于一次查看多行图片。

## 隐私默认设置

- Photos 资产只能通过 PhotoKit 读取。
- App 默认只读，不得修改、删除或整理用户照片。
- OCR、embedding、向量和索引默认保存在本机并在本机处理。
- 不实现人物识别。

## 第 1 里程碑人工检查

- 首次启动：应显示用途和隐私说明，未授权前不读取图库。
- 同意权限：应能选择近一周、近一个月、近一年或全部，并展示所选范围内真实 Photos 图片缩略图和创建时间。
- 拒绝权限：应展示“申请权限”按钮；点击后打开系统设置中的 Photos 权限页面，不崩溃。
- 单图失败：其他图片继续加载，失败数量可见。
- iCloud 图片：可以加载时正常显示；无法加载时显示明确失败原因。
- 全部范围：图库很大时可能加载较慢，但界面不应崩溃，失败数量应可见。

需要保留的截图清单：

- 权限申请前的说明页面。
- 系统 Photos 授权弹窗。
- 授权后的真实图库网格和时间范围切换状态。
- 拒绝或撤销权限后的提示状态。
- 首次遇到的 iCloud 或缩略图读取失败状态。

## 第 2 里程碑人工检查

- 索引状态区：授权并读取图片后，应显示本地索引记录总数。
- 任务状态：读取图片后，OCR 和向量状态初始应显示为 `pending`。
- 去重：重复读取同一时间范围时，未变化数量应增加，不应重复创建记录。
- 重启恢复：重启 App 后，本地索引记录数应能恢复。
- 清除索引：点击清除本地索引后，索引记录归零，但 Photos 原图不受影响。

## 第 3 里程碑人工检查

- OCR 入口：索引状态区应出现“开始 OCR”和“重试失败”按钮。
- 本机处理：点击“开始 OCR”后，App 使用 Apple Vision 在本机处理图片，不上传图片或 OCR 文本。
- 进度状态：页面应展示 OCR pending、processing、ready、failed 数量，以及当前处理进度。
- 性能记录：OCR 完成后应显示平均耗时；失败时应显示主要失败类型。
- 失败恢复：单张图片读取或识别失败不应中断后续图片；失败任务可通过“重试失败”再次处理。
- 样本验收：建议使用中文网页截图、英文文档截图、中英文混排界面、小字号截图和无文字生活照片验证 OCR 效果。

## 第 4 里程碑当前状态

- 已完成：本地 embedding 服务协议、模型 manifest 解析、可打包到 App 的 manifest 模板资源、运行时 manifest 自动加载和缺失降级、Application Support 本机模型包加载和缺失降级、manifest 缺失或模板占位诊断、模型文件大小元数据校验、模型和 tokenizer SHA-256 校验、结构化模型资源清单、资源实际大小与哈希审计、App 内可复制的 manifest 建议字段、本地模型包预检报告、候选 `.mlmodelc` Core ML 加载、运行时模型就绪 Core ML 加载检查、输入输出接口检查、输入 shape 与数据类型校验、研究/评估/非商业许可证限制校验、模型接入清单输出、模型缺失提示、模型就绪度报告、模型资源和配置诊断 UI、模型输入输出与预处理配置校验、图片 NCHW 归一化预处理、后台 utility 推理执行策略、本地 JSON BPE tokenizer 加载和基础 merge 规则处理、文本 token 输入构造、真实 Photos 验证样本描述符、样本描述 JSON 文档解析和隐私安全审计、App bundle 样本描述自动读取、模型与样本描述预检报告、App 内技术验证预检状态展示、App 内运行技术验证按钮和结果摘要展示、App 内视觉查询验证入口、`docs/视觉模型验证样本.example.json` 模板、PhotoKit 样本图片加载桥接、图片编码器 Core ML 推理骨架、文本编码器 Core ML 推理骨架、模型输出向量解析、向量编码/解码、SQLite 向量持久化、模型版本记录、当前模型版本下旧向量需重建状态、交互式视觉索引批量上限、余弦相似度排序测试、视觉索引按钮、失败降级提示、`EmbeddingValidationService` 技术验证入口、可归档到文档中的 Markdown 验证报告输出、技术验证报告和技术验证摘要本机保存到 Application Support，验证报告中的图片编码、相关文本编码、无关文本编码、相似度差距和总耗时记录、`docs/模型接入与验证指南.md`，以及 `docs/视觉模型候选评估.md`。
- 未完成：真实 Core ML 图文双塔模型、与真实模型完全匹配的 tokenizer 验证、真实图片与文本向量同空间验证、中英文查询效果验证。
- MVP 结论：第 4 里程碑按“视觉能力预留、模型验证门禁和安全降级”收口；真实视觉语义搜索不再阻塞第 5、6、7 阶段。后续 MVP 搜索先使用 OCR、时间和基础类型信号。
- 模型约定：App 启动时会优先尝试读取本机 Application Support 下的 `PictureSearch/EmbeddingModelPackage/EmbeddingModelManifest.json`；该目录不存在时再回退到 App bundle 中的 `EmbeddingModelManifest.json`；两处都缺少真实 manifest 时降级为 `local-clip-unconfigured`。真实 manifest 必须记录模型来源、许可证、引入原因、替代方案、影响评估、模型文件名、文件大小、SHA-256、tokenizer、输入输出名、文本起止 token ID 和预处理参数。App 还会尝试读取 `EmbeddingValidationSamples.json` 作为真实 Photos 验证样本描述；缺失或解析失败会进入技术验证预检诊断。`Resources/EmbeddingModelManifest.example.json` 只作为真实模型接入模板，不能作为已验证模型配置。
- 模型候选：`docs/视觉模型候选评估.md` 记录当前候选评估。OpenAI CLIP 是优先候选；Apple MobileCLIP / MobileCLIP2 因模型权重条款限制研究用途，暂不作为默认内置模型；OpenCLIP 生态模型需要逐个确认具体权重许可证。
- 验证要求：真实模型加入后，需要用至少 5 张图片覆盖中文、英文和中英文混合查询，确认图文向量维度一致，且相关查询相似度高于无关查询；验证报告需要包含模型接入清单和模型就绪诊断；缺少任一语言覆盖时不能标记为通过。
- 索引门禁：视觉索引和视觉查询不仅要求模型资源就绪，还要求当前模型版本的技术验证报告或本机验证摘要已经通过；模型版本变化、未运行验证、验证失败或摘要损坏时不会生成视觉向量，也不会返回视觉查询结果。
- 说明：在模型文件和许可证未确认前，App 不会下载模型、不上传图片、不使用人工标签代替视觉搜索。

## 第 5 里程碑人工检查

- 本地搜索：完成 OCR 后，在“本地搜索”输入“包含 Hermes 的截图”，应返回 OCR 命中和类型命中原因。
- 时间查询：输入“去年夏天的截图”或“2025 年 10 月的截图”，应返回时间和类型信号匹配的结果，并把单一弱命中标为相近结果。
- 文档 OCR：输入“文档里的某段文字”，应优先返回 OCR 文本包含该词的图片。
- 纯画面描述：输入“海边夕阳”时，在真实视觉模型未验证前应提示当前 MVP 不能可靠处理纯画面描述查询。
- 结果解释：每条结果应展示高置信或相近结果，以及 OCR、时间或类型命中原因。

## 项目结构

```text
PictureSearch/
  App/
  Features/
  Services/
  Models/
  Resources/
PictureSearchTests/
docs/
```

## 构建

在 Xcode 中打开 `PictureSearch.xcodeproj`，或运行：

```sh
xcodebuild -project PictureSearch.xcodeproj -scheme PictureSearch -destination 'platform=macOS' build
```

## 视觉演示模型

演示模型固定采用 OpenAI CLIP ViT-B/32 的 Core ML 双塔转换产物（MIT）。App 不下载模型；模型包放在
`~/Library/Containers/com.local.PictureSearch/Data/Library/Application Support/PictureSearch/EmbeddingModelPackage/`，包含编译后的图片/文本
`.mlmodelc`、`clip_tokenizer/vocab.json`、`clip_tokenizer/merges.txt` 和真实
`EmbeddingModelManifest.json`。视觉索引按钮会处理当前读取范围内的全部照片；未安装模型时
App 会继续使用 OCR、时间和类型检索，并明确显示视觉模型未就绪。

注意：当前环境的 `xcode-select` 指向 Command Line Tools，因此构建使用 `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild` 和可写 DerivedData 路径执行。正式构建已通过；`xcodebuild test` 能构建测试 bundle，但当前沙盒限制会阻止连接 `testmanagerd.control`，因此 XCTest 已通过直接运行构建出的测试 bundle 完成，61 个测试全部通过。真实 Photos 权限、OCR 真实样本效果、本地搜索结果、视觉语义模型效果和重启恢复仍建议在 Xcode 图形界面中人工复验。

## 测试

```sh
xcodebuild -project PictureSearch.xcodeproj -scheme PictureSearch -destination 'platform=macOS' test
```
=======
# Picture-search
基于 SwiftUI、PhotoKit、Apple Vision 与本地索引构建的 macOS 智能图片搜索应用，支持通过 OCR、时间和图片类型自然语言搜索 Photos 图库，所有数据默认在本机处理。
>>>>>>> 9867aa2904139264cd893d3f82c3ea7c59219294
