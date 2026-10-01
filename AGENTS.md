# AGENTS.md — 本仓库协作约定（给 agent / CI 维护者）

## 代码提交约定
- **改完代码后不自动 commit、不自动 push**。改完代码先停下来等用户确认，用户明确说「提交/push」之后才 commit + push。
- **今后一律如此**：所有代码改动（含新增平台、配置修改、文档更新等）都要等用户确认后才提交。

## 配置修改约定
- **涉及配置类的修改（如 packages.conf / platform 配置 / feeds 的 CONFIG_PACKAGE_* 等），确认配置项准确性时，必须带源代码/文档实证核对，禁止仅凭印象下结论**。
- 具体做法：包名/配置名先在**本地 build 树**（build 树 / feeds 索引 / `.config` 实证）核实——例如用 `feeds/packages.index` 中的 `Package: <name>`、对应包的 `Makefile`（`PKG_NAME`/`define Package/<name>`/`PROVIDES`）、以及 build 树 `.config` 里实际存在的 `CONFIG_PACKAGE_<name>` 符号来确认，而不是靠记忆里的包名猜。
- 教训示例：`stress-ng` 这个包 `PROVIDES:=stress` 只是虚拟别名，`CONFIG_PACKAGE_stress=y` 不生效，必须用真实的 `CONFIG_PACKAGE_stress-ng=y`——这类差异只能靠实证发现，凭印象会踩坑。

### 平台配置（platform/<device>.conf）编写规则
平台专用软件层 conf 由 `scripts/generate-config.sh` 按**行首前缀**强制区分语义，规则如下：
- **`+CONFIG_PACKAGE_<name>=y`** = **附加**该包到本平台（叠加在通用层之上）。平台层加包**必须带 `+` 前缀**。
- **`-CONFIG_PACKAGE_<name>`** = **排除**该包（把通用层已装、但本平台不要的包去掉，输出为 `# ... is not set`）。
- **`CONFIG_<非PACKAGE选项>=<值>`** = **raw 原样透传**（如 `CONFIG_TARGET_ROOTFS_PARTSIZE=768`），不涉及包列表。
- **禁止在平台层写裸 `CONFIG_PACKAGE_x=y`（不带前缀）**：它会被当成 raw 透传或直接丢弃，不生效。裸 `CONFIG_PACKAGE_x=y` 只应出现在**通用层 `packages.conf`**（那里靠正则 `^CONFIG_PACKAGE_([A-Za-z0-9_+.-]+)=y$` 解析，且允许连字符）。
- **包名含连字符时尤其危险**：平台层 raw 分支正则 `CONFIG_[A-Za-z0-9_]*=` 不含连字符，裸写 `CONFIG_PACKAGE_stress-ng=y` 会落入 `*)` 分支被静默丢弃。
- **每个 conf 文件末尾必须留一个换行符**：`while read` 循环对最后一个无 `\n` 的行返回非零，整行静默跳过不生效（real case：`stress-ng` 因处于末行且缺换行，从未被编译进固件）。改完 conf 后核对：`wc -l` 行数应与内容行数一致，且 `generate-config.sh <device>` 后 `grep <packagename> .config` 必须能看到目标包。


## CI 运行约定
- **提交后确保新 CI 立即执行**：每次 push 后，**先等待约 5 秒**（GitHub 推送后 run 尚未注册，立刻查会误判），再检查 actions CI 活跃数量（in_progress + queued）。若活跃 run **≥ 5 个**、或新提交触发的 run 处于 queued 等待（被旧 run 阻塞无法执行），则**取消最旧的 run**，确保**新提交触发的 run 能被放到执行位置马上跑**。
- **活跃 < 5 且新 run 未阻塞时不干预**：让正常 run 自然执行，不主动取消旧 run。
- 例外：用户明确指示取消某批 run 时，以用户指示为准。
