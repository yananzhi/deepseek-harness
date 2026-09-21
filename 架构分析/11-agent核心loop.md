# 11 Agent 核心 Loop

> 本篇是 Agent loop 的“总装图”：纵向从 Workspace 一直拆到工具结果，横向讲主 Agent / 子 Agent，细粒度讲 Attempt 之下，最后回扣三种用户行为。术语定义以 [00-概念总览](00-概念总览.md) 为准，驱动端机制细节见 [02-核心执行循环](02-核心执行循环.md)。本系列没有 `episode`；外层策略迭代叫 `Round`。行号证据指向 `packages/core/agent-loop`、`packages/core/agent`、`packages/core/session` 等源码。

## 0. 名词表：第一次出现即解释

后文直接用英文代号，第一次出现时配中文解释。看到生词回查本节即可。

- **Agent**：自主执行任务的程序主体。后文“主 Agent”指用户直接对话的那个，“子 Agent”指它派出去干活的帮手。
- **Session**：一次对话的全部记录载体，只追加不修改，模型看到的历史都从它派生出来。
- **Workspace**：按目录归档 Session 的分组，可有可无，模型看不见它。
- **Round**：外层策略数出来的“一轮”，只有两种：goal round 与 Ralph round。普通聊天 Turn 不算 Round。
- **goal round**：同一个 Session 里为完成立项目标而续跑的一轮，计入 cap。
- **Ralph round**：开一个全新子 Session 干一轮的结构化多轮工作流中的一轮，轮与轮之间只靠一份有界 handoff 传递状态。
- **cap**：goal round 最多能续跑几轮的配额，实现字段叫 `maxGoalRounds`；已用掉几轮叫 `roundsStarted`。
- **handoff**：Ralph round 之间传递的状态小结，含状态、摘要、证据、下一步、阻塞说明。
- **Turn**：一次输入排空，含零或多个 Step。用户以为的“问一句、等它干完”通常就是一个 Turn。
- **Step**：一次模型请求加它引发的全部工具执行。模型“想一次、调一批工具”就是一个 Step。
- **Attempt**：单次流式模型调用。一个 Step 含一次或多次 Attempt，重试不另起 Step。
- **Stream frame**：Attempt 在界面上逐片吐字的传输单位，分 start、chunk、end 三种。chunk 是暂态的，重放只读落盘结算。
- **Content block**：一次模型回答里的结构化片段，分 text、reasoning、tool-call 等类型。tool-call 靠 id 与 tool-result 配对。
- **Tool pipeline**：一次工具调用要走的固定流水线：pre-execute、guard 否决、dispatch 执行、post-execute、finalize 落盘。
- **guard**：管线里只会否决不会放行的安全检查，默认不通过。
- **Inbox**：每个 Agent 名下的两条待办列表：next-turn 排队列与 next-step 插话列。所有新消息只进 Inbox，不直接砸向模型。
- **claim**：loop 从 Inbox 取走待办的过程，取走才算本 Turn 要读的消息。
- **followup / queue**：默认回车行为，进 next-turn，等整 Turn 结束开新 Turn。
- **steer**：组合键或图标行为，进 next-step，只等当前 Step 结束、同 Turn 继续。
- **inject**：内部程序悄悄塞的上下文，不唤醒 driver，等下个 Step 边界顺带读走。
- **lineage**：父子 Session 之间的身世数据：parentSession、delegationDepth、subagentDepth。只记数据，不决定权限。
- **scope**：以活 Agent 对象为钥匙的注册隔离。子 Agent 不自动继承父的工具与提示词。
- **driver**：loop 里真正转的那根轴，负责取消息、开 Turn、调模型、跑工具，直到没活才停。
- **maintenance**：driver 内部的短暂杂务状态，对外仍显示 idle，期间的唤醒会被暂存重放。
- **initiator**：同进程内标记“这段活是谁发起的”的归因标记，只用于排查，不作权限凭证。
- **surface**：真正会发给模型的那四类记录：system/user/assistant/message + tool/result。`deriveMessages()` 就是从日志算出这份清单的过程。
- **request series**：为复用缓存而划分的请求分组，新 series 写一次完整 request/header。
- **turn-stopping**：模型无欠账时关 Turn 前的最后一道串行终检，有 steer 就加跑一步，无则关 Turn。

```
Workspace（目录分组，可选，模型不可见）
└── Session（只追加日志，一条对话）
    ├── Round（goal round 同 Session / Ralph round 新 Session；普通 human Turn 不是 Round）
    │   └── Turn（一次输入排空：turn/start … turn/end）
    │       └── Step（一次模型请求 + 它引发的全部工具：step/start … step/end）
    │           └── Attempt（单次流式调用：一 Attempt 一事件）
    │               ├── Stream frame：start → chunk* → end（chunk 暂态）
    │               └── Content block：text / reasoning / tool-call（id 配对 tool-result）
    └── Tool pipeline：pre-execute → guard → execute → post-execute → finalize → tool/result
```

| 层 | 打开 | 关闭 | 备注 |
|---|---|---|---|
| Workspace | 创建并挂载 Session | 解绑或归档只删登记，不碰目录与日志 | 模型不可见 |
| Session | `session/created`，起点为 `session/end-seed` | `session/disposed` | live 一对一（agent.id == session.id），落盘后一对多（可 resume 可 fork） |
| goal round | driver `followup` 一条 goal 来源消息并经 pre-step 放行 | 该 Turn 的 `turn/end`，计数记为 `roundsStarted` | 同 Session 一 Turn，开新 request series |
| Ralph round | 起一个全新子 Session（无 seed） | 结构化 `report{continue/complete/blocked}` | 一次 run 横跨多个子 Session |
| Turn | `turn/start`（claim 前） | `turn/end{completed/aborted/blocked/error/max-tokens/interrupted}`，可零 Step | `session/types.ts:270-285` |
| Step | `step/start` | `step/end`；体内 `request/header` → `system/user` → `assistant/message|attempt` → `tool/call→result*` | 重试不重跑 assemble/pre-step |
| Attempt | 无包围事件，`assistant-stream start` | 一 Attempt 一事件：`assistant/message`（进历史）或 `assistant/attempt`（不进历史） | `runtime-types.ts:127-161` |

## 1. 纵向：Session / Round / Turn / Step / Attempt

### 1.1 Session 是地基，不是 Round 之上的又一层 Loop

【你会看到】一条对话就是一个 Session，刷新页面还在；fork 出一条分支后两边各自继续。

正式：Session 是一份只追加的事件日志（`session/src/types.ts:263-268`），模型历史永远由 `deriveMessages()` 从 surface 算出来（`session/src/index.ts:823-842`）。只有 4 种事件进 surface：system/user/assistant/message + tool/result（`types.ts:417-422`）；`assistant/attempt` 只留失败、重试、取消证据，不进历史。**进模型的必先入日志**（`architecture.md:119-125`）。

Agent 与 Session 在 live 一对一（注册要求两者 id 相等，`agent/src/index.ts:456-460`）；落盘后一对多：存档可被新 Agent resume（排他打开并修复崩溃尾），或 fork 给孩子（取到上一个 `turn/end` 的前缀加 `session/end-seed` 切分，`session/src/index.ts:1236-1251`，fork 必须在 Turn 边界）。

### 1.2 Round 之上是 Session；Round 只有两种

普通 human Turn 不是 Round。计数器各归其策略，不数全 Session 的 Turn（`glossary.md:39`）。

- **goal round**：附着于既存 Session 的持久目标（`glossary.md:25-27`）。实现是同 Session `followup` 一条 goal 来源消息（`goal-round-driver/src/index.ts:174-179`），fold 仅当轮号等于 `roundsStarted + 1` 才承认（`goal/src/fold.ts:321-330`），到 cap 则拦停。activation（是否允许续跑，`armed/disabled`）是进程内状态、永不落盘，resume/fork 后一律关闭，需显式指令重开。该 Turn 以 `startsRequestSeries: true` 起步（`:424`）。
- **Ralph round**：一次前台 fresh-agent workflow（`glossary.md:43-45`），一 Round 等于一个全新子 Session，不继承父对话与兄弟对话，只带 immutable objective 加上一轮有界 handoff 再加共享 Workspace（`tool-ralph/src/index.ts:151-174`，`README:12,36`）。agent-loop 包里没有 Ralph mode（`README:61`）。

### 1.3 一个 Round 能装几条用户消息？一个 Turn 呢？

先给结论，再讲故事：**“一 Turn 约等于一条用户消息加后面所有 Agent 工作”只在 idle 单发时成立；忙时一个 Turn 可以吃多条。一个 Round 起步一条，但中途 steer 照收，不另耗 cap。**

为什么？claim 的规矩是（`inbox.ts:109-114`）：首 Step 取走全部 next-step 加一条 next-turn，步间再取全部 next-step。`followup` 的契约写的是所属 Turn 的 sole ordinary message（`runtime-types.ts:217-220`）——ordinary 之外，steer/inject/tool 附带上下文照样能进同 Turn。所以 Turn 是一次排空，不是一条消息。

看小王一下午的三幕：

```
14:00 idle，你发“修 flaky test”
  → Turn#5 = 1 条 user + Step#1（跑测试）+ Step#2（改代码）
  → 这就是你心里的标准像：一条消息，后面全是 Agent。

14:05 Step#1 跑着，你想起“改用 pnpm”，Cmd+Enter 插一句
  → 进 next-step，不打断当前流
  → Step#1 跑完、step/end 之后，下一步的 pre-step 把它认领
  → Turn#5 = 2 条 user（首条 + steer），还是同一个 Turn。
  → 模型在 Step#2 同时看见“测试日志 + 改用 pnpm”，这正是 steer 的用法。

14:06 Step#2 跑着，你又回车“顺便把 lint 修了”
  → 进 next-turn，当前 claim 看不见
  → Turn#5 收尾发现有排队 → 开 Turn#6，首步才取出它
  → Turn#6 = 1 条 user，新 Turn。
```

Round 同理数“轮”，不数“条”：

```
Turn#5（聊天）：修 flaky —— 不是 Round，不耗 cap。
Turn#6（聊天排队）：再修 lint —— 也不是 Round。
立目标“覆盖率到 80%”，driver 发 goal round#1（同 Session 的 Turn#7）
  → 起步 1 条 goal 消息，但 Step#1 跑着时你 steer“先别动鉴权模块”
  → 还是 round#1，不另耗 cap（无关人工 steer 不开新 Round）。
Ralph“重构鉴权，分 3 轮”：
  → round#1 子 Session 甲 → round#2 子 Session 乙 → round#3 子 Session 丙
  → 每轮是一个 Session，里面各自有它的 Turn、Step、若干消息；
  → 每轮只见 objective + 上轮 handoff，看不见 Turn#5 的聊天记录。
```

所以回你的问题：Round 里用户能输多条吗？能，但只有第一条算“本轮立项”，后面插进来的算同轮搭车；Turn 是一条还是多条？idle 是一条，忙时是“首条 queue + 一批 steer”的拼盘。

### 1.4 Turn / Step / Attempt 与 Inbox

Inbox 两列（`agent/src/types.ts:29-36`）：next-turn 排队列与 next-step 插话列。pre-step 内 claim（`agent.ts:245`）：next-step 取光，next-turn 仅首步多取一条（`inbox.ts:109-114`）。`turn/start` 在 claim 前打开（`agent.ts:279`），首步取 next-turn、之后取 next-step（`:285,321`）；turn-stopping 只在已有结束原因且 next-step 为空时串行终检（`:316-319`），有 steer 则同 Turn 再开一步——这就是上面“steer 能把 Turn 撑住”的机关。

Step 形状（`agent.ts:353-499`）：首 Attempt 提交 system/user（`:371-378`）→ `deriveMessages()` 冻结（`:604-610`）→ stream → `assistant/message|attempt` → 有 tool-call 则 `executeToolCalls`（`:489-492`），全归属本 Step；`request-error` 回 retry 则同 Step `continue`（`:449-464`）。上面例子里 Step#1 的测试结果，只有到 Step#2 的模型请求才可见——tool-result 从不插队进正在流的那个 Attempt。

## 2. 横向：主 Agent / 子 Agent

### 2.1 怎么派帮手：one-shot 与 continuable，新鲜起家与 fork 继承

主 Agent 经派活工具调 `ctx.subagents.start / startContinuable` 起帮手（`subagent/src/index.ts:591-621`，`tool-subagent/src/index.ts:526-568`）。没有“delegated Turn”概念：one-shot 是 in-process driver 新建 Agent + Session 只驱动一 Turn（先 `followup` 再等 idle，`in-process-driver/src/index.ts:181-182`）；continuable 是 manager 持有 AgentHandle、以后所有 Turn 走孩子自己的 Inbox 排序（`continuation.ts:104-192`，发消息走 steer、建会话走 queue，`subagent/src/inbox.ts:46-55`）。

种子两种：spawn 新鲜无 seed（`inheritsParentContext=false`）；fork 带到父最后一个 `turn/end` 的已完成前缀。`send_message / interrupt_agent` 只是运行时的薄适配（`tool-subagent-control/src/index.ts:28-116`）。

### 2.2 lineage 是数据，scope 不继承

【插件作者】别指望孩子自动继承父的工具与提示词：scoped 注册天然不继承（`glossary.md:13`），孩子靠显式组合（拼父上下文、影子人格前缀、工具过滤、delegation 上下文，`child-agent.ts:200-219`）。

- scope key 等于活 Agent 对象身份（`glossary.md:14`，`agent.ts:104`）。
- lineage 纯数据（`glossary.md:21`）：parentSession、delegationDepth（持久头部预算，加一超限抛深度超限错）、subagentDepth（读数取最大者防 resume 降级，`depth.ts:28-36`）。运行时 owner（归属人）与持久 lineage 正交（`agent/src/index.ts:210-220,593-597`）。

### 2.3 打断只停当前 Turn，不级联

`interrupt_agent` 文案即契约：只停 current Turn，已排队暂存（parked）、它开的帮手继续跑、自己保持可用、返回即受理（accepted）、已结束则空操作（no-op）（`tool-subagent-control/src/index.ts:78-84`，`subagent/src/index.ts:314-331`）。实现是 `keepInbox: true` 的 `agent.cancel`（`continuation-activation.ts:322-325`），Activation 与已发布后代保留。授权分两路：user 凭持久直系父地址（浏览器面）与 ancestor 凭活体 lineage 校验（模型面），最终映射为 `AgentCancelCause{user|parent}`（`:283-326`）。one-shot 父信号与显式 teardown 才用清空式 `{kind:'parent'}` 并子优先递归（`in-process-driver:168-176`，`finishDisposal:808-830`）。

Agent 可观测只有 idle 与 running（内部 maintenance 对外折叠为 idle，`agent.ts:41-49,114-116`）；AgentHandle 的 dispose 是持有人专有能力；`withInitiator` 只是同进程因果归因（`agent/src/index.ts:324-326,620-650`）。

## 3. 细粒度：Attempt 之下与 ReAct 对应关系

### 3.1 Attempt 等于一次流尝试；之下是 frame、block、pipeline

Step 内先 `prepareRequest`、再 `buildRequest`、再 stream（`agent.ts:363-391`），`AssistantStreamAttempt` 发 start、chunk、end 三类 frame（`assistant-stream.ts:49-109`），chunk 暂态、重放只读落盘结算（`runtime-types.ts:354-357`）。

- 成功落 `assistant/message`（`:467-484`）；模型失败或 abort 或通用异常落 `assistant/attempt`（`:444-448,428-431`）；cancel 有前缀则落带 `interrupted: true` 的 message（`:404-420`）。
- finish 只有 stop、tool-calls、max-tokens、aborted、error（`llm/types.ts:143-149`，缺省 stop）；completed 是 Turn/Step 结束原因，不是 finish。
- Content block 只有 text、reasoning、image、file、tool-call、tool-result（`llm/types.ts:61-132`）；一次回答可混多块，按 index + block-end 保序组装（`assembler.ts:39-84,158-160`）；tool-call 的 id 与 tool-result 的 toolCallId 配对、结果指回调用序号（`tool-calls.ts:263-289`）；max-tokens 丢 tool-call、中断只留非空 text 与 reasoning。

### 3.2 工具批：barrier + 有界池 + 有序提交

`tools/pre-execute` 瀑布、guard 单调否决、`tools/execute` 派发、`tools/post-execute`、finalize/finish（`tools/src/index.ts:146,157,169,191,341-343,453-456`）。parallel 取一片成组、exclusive 单设 barrier（`tool-calls.ts:88-90`），补池遇 exclusive 断组（`:203-205`），上限 `maxParallelToolCalls` 默认 10（`constants.ts:6`）。`commitReady` 只按模型顺序推进连续槽（`:147-161`）。结果可带 `additionalContexts`（进 next-step 下步才可见，`agent.ts:489-492`）与 `concludesTurn`（本步即停，`tool-calls.ts:158`，但不截断已提交的 next-step）。

### 3.3 哪个对应 ReAct？是 Step，不是 Attempt

仓内无 `ReAct` 字符串，只有 loop 实现类名 `ReactLoopAgent`（`agent.ts:72`）。对应物是 Turn 内多 Step 的“调模型、跑工具、再来”循环（`architecture.md:86`，`agent-loop/README:12,75`）：Step 等于 Reason（组装冻结请求加流出助手消息）加 Act（跑工具批）加 Observe（tool-result 落日志到下一步派生重读）。Attempt 只是 Step 内一次流尝试（`firstAttempt + while(true)`，`user/message` 仅首 Attempt 准入）。

四个扩展点位置：`agent/pre-step` 在每步前、早于 `step/start`（`agent.ts:250-256,290,303`）；`agent/request` 在 `prepareRequest` 内、提交 system/users 之前、不能改消息（`:531-534`）；`agent/request-error` 在 settle Attempt 之后、仍在 Step 循环内（`:449-464`）；`agent/turn-stopping` 在 `step/end` 之后、`turn/end` 之前（`:313-320,340`）。

## 4. 用户行为对照：queue / steer / cancel 再发

| 用户行为 | 后端调用 | 落点 | 何时进入上下文 | 是否打断 |
|---|---|---|---|---|
| 回车 queue | `Session.prompt(c,'queue')` → `followup()`（`agent.ts:137-139`） | next-turn + wake | 等整个 Turn 结束，开新 Turn 的独占消息；goal round 也是这条路 | 否 |
| 组合键或图标 steer | `Session.prompt(c,'steer')` → `steer()`（`:141-143`）或把已排队行搬到 next-step | next-step + wake | 只等当前 Step 结束，同 Turn 下一步，可阻止 Turn 关闭（`:315-321`） | 否，从不 abort |
| 点 Stop 再发 | `cancel({kind:'user'},{keepInbox:true})`（`commands.ts:511`）再 `followup` | abort 当前 Turn、排队保留；abort 后 wake 重分类到 next-turn（`agent.ts:131-133`） | 新消息开新 Turn | 是，协作式 abort 整个 Turn |

cancel 不回滚：日志只追加，已落盘全保留。cancel 只做截断流、drain 已派发、给未派发各补 `ABORTED_BEFORE_DISPATCH` 合成对、记 `turn/end{aborted}`（`agent.ts:149-155,403-431`，`tool-calls.ts:221-242`）。

接小王的故事讲完：14:07 你觉得 Step#2 的改码改歪了，点 Stop 再发“别改了，直接说结论”。搜索结果留着，没派上的改码留一条 abort error，有前缀的流以 `interrupted: true` 留着——新 Turn#6 照样看见半截历史，模型会说“我看到你打断了改码，已跑完的测试结果是……”。“记得被打断的事”是符合设计的；真想清掉半截，只能走 compaction 或 surface 替换，cancel 本人不删历史。

## 5. 层级总图：左边概念，右边真实例子

左列是 loop 层级，右列是小王一下午实际发生的事。同一行左右对照看：每条用户手势落在左列哪一层。

```
层级（左）                              真实例子（右）
──────────────────────────────────      ──────────────────────────────────
Session：一条对话的全部日志             同一 Session：一下午修测试的全部记录
│                                       │
├─ human Turn#5（非 Round）              │ 14:00“修 flaky test”＋ steer“改用 pnpm”
│  ├─ Step#1：请求＋工具批              │   Step#1：跑测试（Bash）→ 日志落盘
│  │  └─ Attempt#1：单次流式调用        │     Attempt#1：一次流出“先跑测试”＋工具调用
│  │     ├─ frame：start→chunk→end      │       chunk 在界面逐字冒出来
│  │     └─ block：text＋tool-call      │       text＋两个 tool-call（测试＋搜索）
│  ├─ Step#2：请求＋工具批              │   Step#2：认领 steer“改用 pnpm”→ 改码
│  └─ turn/end（completed）             │   14:05 的 steer 把 Turn 撑住，同轮收尾
│                                       │
├─ human Turn#6（queue 开的新 Turn）     │ 14:06“顺便把 lint 修了”（回车 queue）
│  └─ Step#1 …                          │   等 Turn#5 结束才开的新 Turn
│                                       │
├─ goal round#1（同 Session 的 Turn#7）  │ /goal“覆盖率到 80%”＋ steer“先别动鉴权”
│  └─ Turn#7：goal 消息＋人工 steer      │   还是同一 Round，不另耗 cap
│                                       │
└─ Ralph run（横跨 3 个子 Session）      │ “重构鉴权，分 3 轮”
   ├─ round#1：子 Session 甲             │   只见 objective＋空 handoff，修完写 handoff
   ├─ round#2：子 Session 乙             │   只见 objective＋第 1 轮 handoff
   └─ round#3：子 Session 丙             │   只见 objective＋第 2 轮 handoff，看不见 Turn#5
```
