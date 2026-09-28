# AGENTS.md — 本仓库协作约定（给 agent / CI 维护者）

## 代码提交约定
- **改完代码后不自动 commit、不自动 push**。改完代码先停下来等用户确认，用户明确说「提交/push」之后才 commit + push。
- **今后一律如此**：所有代码改动（含新增平台、配置修改、文档更新等）都要等用户确认后才提交。

## 配置修改约定
- **涉及配置类的修改（如 packages.conf / platform 配置 / feeds 的 CONFIG_PACKAGE_* 等），确认配置项准确性时，必须带源代码/文档实证核对，禁止仅凭印象下结论**。
- 具体做法：包名/配置名先在**本地 build 树**（build 树 / feeds 索引 / `.config` 实证）核实——例如用 `feeds/packages.index` 中的 `Package: <name>`、对应包的 `Makefile`（`PKG_NAME`/`define Package/<name>`/`PROVIDES`）、以及 build 树 `.config` 里实际存在的 `CONFIG_PACKAGE_<name>` 符号来确认，而不是靠记忆里的包名猜。
- 教训示例：`stress-ng` 这个包 `PROVIDES:=stress` 只是虚拟别名，`CONFIG_PACKAGE_stress=y` 不生效，必须用真实的 `CONFIG_PACKAGE_stress-ng=y`——这类差异只能靠实证发现，凭印象会踩坑。

## CI 运行约定
- **提交后确保新 CI 立即执行**：每次 push 后，**先等待约 5 秒**（GitHub 推送后 run 尚未注册，立刻查会误判），再检查 actions CI 活跃数量（in_progress + queued）。若活跃 run **≥ 5 个**、或新提交触发的 run 处于 queued 等待（被旧 run 阻塞无法执行），则**取消最旧的 run**，确保**新提交触发的 run 能被放到执行位置马上跑**。
- **活跃 < 5 且新 run 未阻塞时不干预**：让正常 run 自然执行，不主动取消旧 run。
- 例外：用户明确指示取消某批 run 时，以用户指示为准。
