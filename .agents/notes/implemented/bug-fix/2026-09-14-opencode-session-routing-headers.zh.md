# Agent Note: Session routing headers on every LLM adapter

Status: implemented

[English](2026-09-14-opencode-session-routing-headers.md) | 中文

## Problem

缺少 session 的聊天请求会被 OpenCode Go 以 `400 MissingSessionID`（`Request is missing x-opencode-session`）拒绝。Harness 只在 direct-fetch DeepSeek adapter 上发送原生的 `x-deepseek-harness-session-id` 头；pi-ai adapter 的请求完全不带 session 头。已安装的 pi-ai（0.85.1）不支持 `x-opencode-session`——它的 `sessionId` 流选项只会喂给其他 provider 使用的、可选的 `x-session-affinity` 头——因此 loop 打上的 session id 在这条路径上从未到达 wire。Go 自己的客户端表格把 DeepSeek Harness 列为问题客户端，原因正是如此：部分模型路径带 session 信息，部分路径缺失。

## Decision

`@deepseek-ai/dsh-llm` 新增 `sessionHeaders()` 构造每次请求的 session 路由头；两个生产 adapter 在每次携带 session 的聊天请求上都发送这两个头：文档规定的 `x-opencode-session`，以及 direct-fetch adapter 已在发送的原生 `x-deepseek-harness-session-id`。无 session 的调用两个都不发。在 pi-ai 路径上，harness 的值覆盖同名 deployment `headers`，因为路由必须跟随 loop 打上的会话身份，而不是静态配置字符串。原生头保留而非替换：Go 认它，其他 OpenAI 兼容端点会忽略未知头，删除则会带来 harness 看不见的消费者风险。

## Alternatives considered

**只把原生头扩展到所有 adapter。** 这正是 Go 客户端表格字面上要求的（"send it across all adapters"）。落选原因是实际观测到的 `400` 点名要 `x-opencode-session`，按文档契约修是最稳的目标；两个头都发只多一个头，两种解读都满足。

**只发 `x-opencode-session`，去掉原生头。** 原生头已在 DeepSeek 路径随生产流量发送，去掉是兼容性风险，对路由毫无增益。加法变更让回滚就是一次 revert。

**按 profile 做配置开关。** Session 路由身份归 loop 所有，不是随部署变化的可调项：一个没人打开的开关只会复现本次故障；也不存在希望自己会话不可路由的合法部署。

## Consequences

两个 adapter 上带 session 的聊天请求各多两个头；无 session 调用的字节与之前完全一致。Helper spec 锁定映射关系与空 case；各 adapter spec 分别锁定存在、缺席，以及（pi-ai）覆盖 deployment 头的优先级，新模块保持全覆盖。两个 adapter README 均已点名这两个头。若某网关拒绝未知头，这个加法修复会变成故障；但受支持的 OpenAI 兼容端点都不这样做，且 direct-fetch adapter 在生产环境早已发送自定义 `x-deepseek-harness-*` 头。
