# GitHub AI 自启动治理规则包

> 本文件由自启动规则包的根 README 迁移而来。为了不覆盖 GPTWebKit 已有产品 `README.md`，治理包说明保存在 `docs/project/`；真正的权威入口仍是根目录 `AGENTS.md` 与 `docs/project/START_HERE.md`。

这是一个可直接复制到新 GitHub 仓库根目录的通用 AI 开发治理模板。

目标：

- 新项目不需要逐个上传项目 MD 给 AI；
- AI 首次进入仓库时自动识别项目用途、语言/框架、构建方式、测试方式、版本来源、关键模块与当前状态；
- AI 主动维护项目资料和当前进度，不等待用户提醒；
- 支持规则会话与多个功能开发会话并行；
- 每个功能任务拥有独立 checkpoint、branch、PR 和测试候选身份；
- 支持直接用功能名称续接 Active 任务；
- 会话类型或任务身份不明确时必须询问用户，禁止猜测；
- 并行开发前主动检查文件、状态所有者、核心模块、依赖和版本/Build 冲突；
- 会话突然达到上下文上限时，可依靠 GitHub 中的最近 checkpoint 续接；
- 功能完成后把长期结论归档到项目资料，并移除 current checkpoint。

## 使用方法

1. 将本规则包中的治理文件复制到仓库。
2. 在 ChatGPT Project / 其他 AI 项目的项目指令中填入仓库地址，并粘贴随包提供的统一启动指令。
3. 新会话直接说要做什么，例如：`当前为规则会话`、`当前为功能会话，新任务：详情页优化`、`详情页优化`。
4. AI 必须先读取 `AGENTS.md` 和 `docs/project/START_HERE.md`，再按仓库中的当前资料工作。

## 首次自启动

如果 `docs/project/PROJECT_PROFILE.md` 标记为 `Initialization: Pending`，AI 应自动执行只读仓库调查并初始化项目资料，包括 README/docs、源码与入口、语言/框架、依赖清单、构建/测试/CI、版本来源、部署环境、关键模块和状态所有者。

初始化时不得猜测。无法证明的信息写成 `Unknown / Unverified`，并记录证据来源。初始化只更新治理/项目资料；除非用户本身要求开发，否则不要顺手修改产品代码。

## 自动维护

AI 不应等待用户说“更新文档”。重要实现、CI/测试、Artifact、运行时结果、架构决定、依赖、版本/Build、部署、模块状态、项目画像或功能基线变化后，应在同一轮主动更新对应 checkpoint / 项目资料。

不要为了每个微小编辑制造文档噪音；只记录具有独立续接价值的里程碑。

## 目录说明

- `AGENTS.md`：仓库级 AI 总规则。
- `docs/project/START_HERE.md`：新会话唯一入口。
- `docs/project/PROJECT_PROFILE.md`：项目用途、技术栈、构建测试、版本体系等稳定画像。
- `docs/project/PROJECT_STATE.md`：当前项目状态和真实基线。
- `docs/project/MODULE_STATUS.md`：模块状态、Frozen/Stable/Active 等。
- `docs/project/TECHNICAL_DECISIONS.md`：已验证决策和否决路线。
- `docs/project/BUILD_TEST_INDEX.md`：Build/Release/Test candidate 与验证证据索引。
- `docs/project/PROJECT_SPECIFIC_RULES.md`：项目专属合同、兼容规则、业务红线。
- `docs/project/CURRENT_WORK.md`：规则会话 / 开发会话类型路由。
- `docs/project/CURRENT_WORK_RULES.md`：规则维护 checkpoint。
- `docs/project/CURRENT_WORK_DEV.md`：开发任务路由器。
- `docs/project/current/dev/README.md`：并行功能任务 checkpoint 规范。
- `docs/project/current/dev/DEV-*.md`：每个仍在进行中的功能自己的 checkpoint。
- `docs/project/DOCUMENTATION_POLICY.md`：文档权威和自动维护规则。
- `.github/copilot-instructions.md`：GitHub Copilot 短版 standing rules。
- `.github/skills/project-change-review/SKILL.md`：通用变更审查 Skill。
