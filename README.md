# dsh-companion-kit

> 让 AI 伙伴住进 QQ 的**部署套件**：NapCat 的启动/看门狗脚本、一个多角色本地群聊插件、几份补丁，以及踩坑记录。
>
> 这不是"又一个 QQ 机器人框架"。它不包含任何上游插件的代码——它负责**把它们拼起来、并让你在半夜掉线时不用手动救**。

⚠️ **风险声明（先读）**
- NapCat 是第三方 QQ 运行时，与腾讯无关。**自动化操作 QQ 有封号风险**，只建议用不心疼的小号。
- 本仓库不含任何真实账号、密码、cookie、聊天记录。
- 角色人设如涉及第三方作品（如蔚蓝档案），属同人二创，**禁止商用**。
- 作者不对封号、数据丢失、任何后果负责。

---

## 它解决什么问题

把「DSH 里的 AI 会话」接到「你的 QQ」上，通常要自己拼四五样东西，然后遇到这些事：

| 症状 | 这个仓库给的东西 |
|---|---|
| NapCat 进程活着，但登录掉了，一直出二维码 | `watchdog.ps1` —— 能识别「进程在、没登录」，退避重启 |
| 每次开机都要手动点一次启动脚本 | `register-tasks.ps1` —— 登录自启 + 5 分钟巡检 |
| 启动时黑框一闪 | `run-hidden.vbs` —— wscript 无窗壳 |
| 想让几个角色在同一个群里聊天 | `plugins/group-chat` —— 原创插件 |
| 改完 DSH 插件被更新覆盖 | `patches/` —— 目的模式等补丁 |

---

## 全景

```
你的 QQ
   │
   ▼
NapCat（第三方，自行安装）   OneBot HTTP :3000 / WebUI :6099
   │  轮询
   ▼
dsh-qq-bridge（上游插件）    收发消息
   │  agent.followup()
   ▼
DSH 会话「聊天」
   ├─ dsh-fish-memory   长期记忆（会淡忘）
   ├─ dsh-feiyu-mood    心情
   └─ dsh-speak-up      主动开口
```

细节见 [docs/架构.md](docs/架构.md)。

---

## 本仓库有什么 / 没有什么

**有**

```
docs/            架构、部署、故障排查、风险与合规
scripts/napcat/  启动器、看门狗 v2、无窗壳、配置加载
scripts/register-tasks.ps1   一键注册计划任务
plugins/group-chat/          原创：多角色本地群聊插件
patches/                     对上游插件的改动（speak-up 目的模式）
config/                      脱敏配置模板
```

**没有**（需要自己装，各自 MIT）

- `dsh-qq-bridge`、`dsh-speak-up`、`dsh-feiyu-mood`、`dsh-fish-memory` —— 上游插件
- NapCat / QQ NT 运行时 —— 第三方，请从官方 Releases 自取
- 任何账号、密码、token

---

## 三步开始

```powershell
# 1. 把 NapCat 装好（路径随意，比如 D:\NapCat），确认能登录

# 2. 配置
cd scripts\napcat
copy napcat.conf.example.json napcat.conf.json
notepad napcat.conf.json      # 改 NapCatDir / QQAccount

# 3. 注册计划任务
cd ..\..
powershell -ExecutionPolicy Bypass -File scripts\register-tasks.ps1
```

之后：登录 Windows → NapCat 自动起；每 5 分钟看门狗巡检一次；
掉登录会被自动重启（最多 3 次，之后在 `napcat-watchdog.log` 里留下「需要人工扫码」）。

完整步骤见 [docs/部署.md](docs/部署.md)。

---

## group-chat 插件

把几个 DSH 会话拉进一个本地群：谁说完一轮，就把话转给群里其他人，带名字和轮次上限。

```
成员 A 说完 → 转给 B → B 回复 → 转回 A → … 最多 4 跳就停
```

三层防炸环：一波最多 4 跳 / 10 分钟静默算新一波 / 每会话每小时 8 次。
详细用法见 [plugins/group-chat/README.md](plugins/group-chat/README.md)。

---

## 许可

本仓库原创部分：MIT（见 [LICENSE](LICENSE)）。
上游插件各自遵循其原许可（均为 MIT），版权归原作者。

文档：CC BY 4.0（引用请注明来源）。
