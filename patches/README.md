# 补丁

对**上游插件**的改动。上游都是 MIT，正确做法是 fork + PR，所以这里只放 diff。

## speak-up-0.2.3-local.patch

基于 `dsh-speak-up` **0.2.3** 的本地合集补丁（27.5 KB，391 行新增）。包含六件事：

| # | 内容 | 来源 |
|---|---|---|
| 1 | **目的模式**：开口前先挑一个具体由头（关心 / 分享 / 好奇 / 续聊），最近 6 条不重复 | 本地新增 |
| 2 | **目的用模型**：真发时用一次很短的模型调用（maxTokens 800），从最近 8 条对话里想一句由头；失败退回词库 | 本地新增 |
| 3 | **自动唤醒**：目标会话没活着时先 `sessionController.resolveAgent` 叫醒它（10 秒超时） | 本地新增 |
| 4 | **两道闸门**：主人刚说过话不打扰（默认 15 分钟）、每天最多开口 N 次（默认 10） | 本地新增 |
| 5 | **接口安全门**：`/save` `/roll` `/new-session` 只收 POST（GET 回 405），跨站来源回 403 | 回移上游 0.3.0 |
| 6 | **冷却判定**：不再「投递成功就算开口」，改成真的出现有正文的 `assistant/message` 才算 | 回移上游 0.2.9 |

新增配置：`自动唤醒`、`目的模式`、`目的用模型`、`每日上限`、`主人在聊分钟`。
状态文件：`~/.dsh/speak-up-purpose.json`（日期 / 今日次数 / 最近用过的由头）。

### ⚠️ 与上游的一处**故意不同**

上游 0.3.x 的安全门会先问宿主的 `connection.requestRejection`。在本机实测（DSH 0.2.1-rc.5 桌面端），
这个函数对**本机脚本和桌面端请求一律回 401** —— 连设置页读 `/state` 都会被挡。

所以补丁里只保留「看来源」那一层：

```
跨站（sec-fetch-site: cross-site 或外域 Origin）→ 403
本机页面（dsh-app:// / 127.0.0.1 / localhost）与无来源的本地调用 → 放行
```

跨站页面发请求时浏览器必定带 `Origin` 或 `sec-fetch-site`，这一层够用。

### 用法

```bash
# 先检出 dsh-speak-up 的 0.2.3
git checkout v0.2.3        # 或对应的 tag/commit
git apply patches/speak-up-0.2.3-local.patch
node --check lib/host.js
```

> ⚠️ **不要直接打到 0.3.x 上**：上游在 0.2.4~0.3.1 之间重构过路由和会话清单，
> 两边冲突（实测 `patch does not apply`）。要用新版上游，得把上面六件事照着重新实现一遍。

### 实测

```
GET  /roll            → 405
POST /roll 跨站        → 403
POST /roll 本机/无来源  → 200
GET  /state           → 200（只读接口不上 POST 闸）
```

## 还没整理成补丁的

- **qq-bridge 的补发/水位/不吞消息**：见 [qq-bridge-补发.md](qq-bridge-补发.md)——
  不是可 apply 的 diff，是**设计说明 + 关键代码**。原因写在文件开头：
  本机是 0.3.6，上游已改名 `dsh-qq-link` 并到 1.5.x，结构差太多，硬凑 diff 会害人。
- **bili-subagent 的登录真验**：把 `loggedIn: hasCredential()`（看文件在不在）换成真打
  `web-interface/nav` 看 `isLogin`，缓存 5 分钟。上游 0.9.8 仍是文件判断，所以这份改动还没合回去。

欢迎把自己那份 diff 提上来。
