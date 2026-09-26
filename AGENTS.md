# AGENTS.md — 本仓库协作约定（给 agent / CI 维护者）

## CI 运行约定
- **旧 CI run 不用停**：push 触发的新 run 与仍在跑的旧 run 可并行，不要主动取消旧 run。
  多个 run 同时跑没关系，出结果后再逐个排查问题。
