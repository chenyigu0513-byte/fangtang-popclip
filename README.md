# 方糖：划词收藏，随手摘录

选中文字，保存到 Obsidian；支持手动或 AI 分类，方便日后查找。

方糖是基于 PopClip 的 macOS 文字摘录扩展。选中文字后，选择一个标签，就能发起保存；也可以按需使用 DeepSeek 自动分类。

> 首次公开发布准备中。请先按下方步骤完成安装和测试；正式下载链接与演示将在发布后补充。

## 能做什么

- 手动分类：SOP、技巧、案例、观点、灵感、待整理。
- 保存选中原文，并在可获取时保留网页来源或应用名。
- 当天首条加入日期标题，每条包含时间和标签。
- 可选 AI 分类：从六种标签里选一类，不改写原文。
- 本地月度 token 计数、预警和请求前额度检查。
- AI 不可用时，回退到“待整理”并继续尝试保存原文。

示例内容（虚构）：

```markdown
## 2026年9月21日 · 星期一

- 10:30 #技巧
  > 做评审前，先写下这次需要确认的三个问题。
  来源：示例文档
```

## 使用前准备

1. macOS 上安装 PopClip 与 Obsidian。
2. 在 Obsidian 中安装并启用 Advanced URI 社区插件。
3. 准备接收摘录的知识库与笔记。
4. 需要 AI 分类时，再配置自己的 DeepSeek API Key。手动分类不需要 Key。

可选：项目提供了 Obsidian 标签配色代码片段，让 SOP、技巧、案例、观点、灵感和待整理显示为不同颜色。安装方法见 [`obsidian/README.md`](obsidian/README.md)。

## 当前源码安装方式

获取项目源码后，打开 `YuDeZaShiBu.popclipext` 文件夹安装到 PopClip。扩展内显示名为“方糖”，技术目录名暂时沿用旧称。若系统无法直接识别文件夹，应等待经过验证的发布包，不将此路径视为已完成的新用户安装验证。

在扩展设置中填写自己的知识库和笔记名。知识库名和目标笔记名需要在扩展设置中自行填写；未填写时不会发起保存。

先选一小段测试文字，用手动标签保存，并进入 Obsidian 确认内容实际出现，再开始日常使用。

如果希望让 Codex 协助安装，可以把本仓库地址发给它，并说明：请检查 `YuDeZaShiBu.popclipext` 的配置、指导我在 Obsidian 启用 Advanced URI、安装扩展，并协助我完成一次测试保存。知识库名和目标笔记名由我在本机确认，DeepSeek API Key 只在 PopClip 设置中填写，不发送到聊天或提交到仓库。安装完成后可按自己的标签习惯修改 `Config.yaml`，再重新安装扩展。

## 数据与 AI 用量

手动分类不向 DeepSeek 发送请求。点击 AI 时，会发送固定分类提示词及当前选中文字；不会把来源 URL、页面标题、应用名、知识库名或整本笔记作为请求字段发送。若选中文字本身包含敏感信息，它也会进入请求。

Key 通过 PopClip 的 secret 设置读取，不写入源码或用量记录。脚本会在本地临时保存请求和响应，正常退出时清理；异常终止可能留下临时文件。

默认自然月额度为 100,000 tokens，预警比例 80%，可在设置中更改。用量仅覆盖本扩展，不统计同一 Key 在其他工具中的调用。网络结果不确定时保留预留额度，因此本地计数可能高于实际账单。

历史兼容状态目录为 `~/Library/Application Support/YuDeZaShiBu/`，其中 `usage.json` 存储用量，`capture.json` 存储日期标记。当前保护仍需完善并发安全，不提供账号级费用硬上限保证。

## 已知边界

- 当前仅接入 Obsidian；没有 Notion 直连、OCR、自动复习或系统级剪贴板监控。
- 文字选取、浮层位置和来源获取受 PopClip 及当前应用限制；不保证任何网页或文档均可使用。
- 不保留图片、字体和复杂表格等富文本。
- 通过 Advanced URI 发起追加，脚本尚不能确认最终笔记落盘；需检查实际笔记结果。
- 同日切换目标笔记时，日期标题可能缺失，待修复。
- AI 选中文本超过 4,000 字符时不调用模型，回退到“待整理”。

## 开发与测试

在项目目录中运行：

```sh
/bin/zsh tests/test_capture.sh
```

当前模拟测试结果：57 项断言通过，0 失败（2026-09-24）。测试替换了网络和打开笔记的操作，不调用真实 API。真实应用兼容性与新用户安装仍需另行验证。

代码集中在 `YuDeZaShiBu.popclipext/`，测试位于 `tests/`。技术标识沿用旧名，以避免随意迁移本地用量状态。

## 关于这个项目

方糖从一个个人需求开始：在阅读时，把值得留下的片段顺手送进自己的笔记。产品需求、使用反馈和命名由作者主导，代码与文档通过 AI 辅助实现。选词浮层来自 PopClip。

[阅读作品集案例](docs/方糖：划词收藏，随手摘录.md)。

英文名尚未确定。本项目采用 [MIT 许可证](LICENSE)。

## English overview

方糖 is a lightweight macOS text-capture extension for PopClip. It sends selected text to Obsidian with a category and available source information. Manual tagging works without an AI API request. Optional DeepSeek classification includes local usage tracking and a pre-request budget check.

Requires PopClip, Obsidian, and the Advanced URI plugin. This project is being prepared for its first public release. A local budget check is not an account-wide spending limit, and opening an Obsidian URI does not confirm that the note was written.
