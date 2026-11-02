// dsh-group-chat —— 本地群聊原型
//
// 机制：某个「成员会话」说完一整轮 → 把最后那句转给群里其他成员（agent.followup），
//      带上〔名字〕和轮次标记，并做三层防炸环：
//        ① 一波最多 maxHops 跳（默认 4）
//        ② 一波静默 cooldownMin 分钟后计数归零
//        ③ 每个会话每小时最多 perHour 次（默认 8）
//
// 不碰任何外部协议、不联网。

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'
import { homedir } from 'node:os'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { randomUUID } from 'node:crypto'

export const name = 'group-chat'
export const inject = ['agents', 'sessions', 'sessionTitle', 'webServer']

const 家 = process.env.DSH_HOME || join(homedir(), '.dsh')
const 配置文件 = join(家, 'group-chat.json')
const 路由前缀 = '/dsh-group'
const 日志上限 = 80

const 默认配置 = {
  启用: false,
  成员: [],          // [{ id: 'session-xxx', 名字: '小星' }]
  最多跳数: 4,        // 一波最多转几次
  冷却分钟: 10,       // 多久没动静算新的一波
  每小时上限: 8,      // 每个会话每小时最多转几次
}

function 归一化(原始) {
  const o = 原始 && typeof 原始 === 'object' && !Array.isArray(原始) ? 原始 : {}
  const 成员 = Array.isArray(o.成员)
    ? o.成员.filter((m) => m && typeof m.id === 'string' && m.id.trim())
        .map((m) => ({ id: m.id.trim(), 名字: String(m.名字 || '').trim() || m.id.trim() }))
    : []
  const 数 = (v, d, lo, hi) => {
    const n = Math.round(Number(v))
    return Number.isFinite(n) ? Math.max(lo, Math.min(n, hi)) : d
  }
  return {
    启用: o.启用 === true,
    成员,
    最多跳数: 数(o.最多跳数, 4, 1, 12),
    冷却分钟: 数(o.冷却分钟, 10, 1, 240),
    每小时上限: 数(o.每小时上限, 8, 1, 60),
  }
}

function 读配置() {
  try { return 归一化(JSON.parse(readFileSync(配置文件, 'utf8'))) } catch { return 归一化(null) }
}

function 写配置(c) {
  try {
    mkdirSync(家, { recursive: true })
    writeFileSync(配置文件, JSON.stringify(c, null, 2), 'utf8')
    return true
  } catch { return false }
}

const 会话键 = (v) => {
  const s = String(v == null ? '' : v).trim()
  return s.startsWith('session-') ? s.slice('session-'.length) : s
}

export function apply(ctx) {
  const 日志 = []
  记账('群聊插件已加载（默认关闭，去 /dsh-group/state 看配置）')

  function 记账(文本) {
    const d = new Date()
    const 补 = (n) => String(n).padStart(2, '0')
    const 时间 = `${补(d.getMonth() + 1)}-${补(d.getDate())} ${补(d.getHours())}:${补(d.getMinutes())}:${补(d.getSeconds())}`
    日志.push({ 时间, 文本 })
    if (日志.length > 日志上限) 日志.shift()
    try { ctx.logger?.info?.(`group-chat: ${文本}`) } catch {}
  }

  // ── 防炸环的计数器 ──
  let 本波 = { 跳数: 0, at: 0 }
  const 每会话 = new Map() // 键 -> { 时间戳数组 }

  function 取本波(cfg) {
    const now = Date.now()
    if (now - 本波.at > cfg.冷却分钟 * 60_000) 本波 = { 跳数: 0, at: now }
    return 本波
  }

  function 今日还能转(cfg, 键) {
    const now = Date.now()
    const 窗口 = 60 * 60_000
    const 记 = (每会话.get(键) || []).filter((t) => now - t < 窗口)
    每会话.set(键, 记)
    if (记.length >= cfg.每小时上限) return false
    记.push(now)
    return true
  }

  // ── 找 agent（会话 id 有两种写法，都试） ──
  function 找agent(id) {
    const 原 = String(id || '')
    for (const 试 of [原, `session-${会话键(原)}`]) {
      try {
        const a = ctx.agents?.get?.(试)
        if (a && typeof a.followup === 'function') return a
      } catch {}
    }
    return undefined
  }

  // ── 记录每个会话「这一轮最后说的话」 ──
  const 最近一句 = new Map()

  function 提取正文(消息) {
    const 块 = Array.isArray(消息?.content) ? 消息.content : []
    return 块.filter((b) => b && b.type === 'text' && typeof b.text === 'string')
      .map((b) => b.text).join('\n').trim()
  }

  async function 转给其他人(来源键, 名字, 正文, cfg) {
    const 本 = 取本波(cfg)
    if (本.跳数 >= cfg.最多跳数) {
      记账(`这一波已经转了 ${本.跳数} 跳，按上限停下（防炸环）`)
      return
    }
    本.跳数++
    本.at = Date.now()

    const 目标们 = cfg.成员.filter((m) => 会话键(m.id) !== 来源键)
    let 成功 = 0
    for (const m of 目标们) {
      if (!今日还能转(cfg, 会话键(m.id))) {
        记账(`跳过 ${m.名字}：这一小时转得太频繁了`)
        continue
      }
      const agent = 找agent(m.id)
      if (!agent) {
        记账(`跳过 ${m.名字}：那个会话现在没活着`)
        continue
      }
      const 文案 = `【群聊 ${本.跳数}/${cfg.最多跳数}·${名字}】${正文.slice(0, 1200)}`
      try {
        await agent.followup({
          id: randomUUID(),
          role: 'user',
          content: [{ type: 'text', text: 文案 }],
          source: { kind: 'group-chat' },
        })
        成功++
      } catch (e) {
        记账(`转给 ${m.名字} 失败：${String((e && e.message) || e)}`)
      }
    }
    if (成功) 记账(`${名字} 的话转给了 ${成功} 个人（第 ${本.跳数} 跳）`)
  }

  // ── 监听会话事件 ──
  ctx.effect(() => {
    const 摘 = ctx.on('session/event', (session, event) => {
      try {
        const 键 = 会话键(session?.id ?? session)
        const cfg = 读配置()
        if (!cfg.启用) return
        const 我 = cfg.成员.find((m) => 会话键(m.id) === 键)
        if (!我) return

        if (event?.type === 'assistant/message') {
          if (event.data?.interrupted) return
          const 文 = 提取正文(event.data?.message)
          if (文) 最近一句.set(键, 文)
          return
        }

        if (event?.type === 'turn/end') {
          const 因 = event.data?.reason?.kind
          if (因 && 因 !== 'completed') { 最近一句.delete(键); return }
          const 文 = 最近一句.get(键)
          最近一句.delete(键)
          if (!文) return
          if (文.startsWith('【群聊')) return  // 别把群聊原文再转一圈
          void 转给其他人(键, 我.名字, 文, cfg)
        }
      } catch (e) {
        记账(`处理事件出错：${String((e && e.message) || e)}`)
      }
    })
    return () => { try { if (typeof 摘 === 'function') 摘() } catch {} }
  }, 'group-chat: 盯成员会话')

  // ── 路由 ──
  const 回 = (res, obj, code = 200) => {
    res.writeHead(code, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' })
    res.end(JSON.stringify(obj))
  }
  const 读体 = (req) => new Promise((resolve) => {
    let s = ''
    req.on('data', (c) => { s += c; if (s.length > 262144) req.destroy() })
    req.on('end', () => { try { resolve(JSON.parse(s || '{}')) } catch { resolve({}) } })
    req.on('error', () => resolve({}))
  })

  function 活着会话() {
    const 出 = []
    try {
      const 表 = ctx.sessions?.list?.() || []
      for (const s of 表) {
        const id = String(s?.id ?? s)
        let 标题 = ''
        try {
          const t = ctx.sessionTitle?.get?.(s)
          标题 = String(t?.title || t?.标题 || '') || ''
        } catch {}
        出.push({ id, 标题, 键: 会话键(id) })
      }
    } catch {}
    return 出
  }

  ctx.effect(() => ctx.webServer?.register?.({
    kind: 'prefix',
    path: 路由前缀,
    handler: async (req, res) => {
      const url = new URL(req.url, 'http://127.0.0.1')
      const p = url.pathname

      if (p === `${路由前缀}/state`) {
        const cfg = 读配置()
        return 回(res, { ok: true, 配置: cfg, 活着的会话: 活着会话(), 日志, 配置文件 })
      }

      if (p === `${路由前缀}/save`) {
        const 来 = await 读体(req)
        const 新 = 归一化({ ...读配置(), ...(来 && typeof 来 === 'object' ? 来 : {}) })
        if (!写配置(新)) return 回(res, { ok: false, 说: `写不进配置：${配置文件}` })
        记账(`设置已保存：启用=${新.启用} 成员=${新.成员.map((m) => m.名字).join('/')} 最多${新.最多跳数}跳`)
        return 回(res, { ok: true, 配置: 新, 日志 })
      }

      // 读某个会话最近的对话（用宿主的 sessionController.inspect，不碰磁盘）
      if (p === `${路由前缀}/transcript`) {
        const 会话 = url.searchParams.get('session') || ''
        const 条数 = Math.max(1, Math.min(40, Number(url.searchParams.get('n')) || 8))
        const sc = ctx.get && ctx.get('sessionController')
        if (!sc || typeof sc.inspect !== 'function') {
          return 回(res, { ok: false, 说: '没有 sessionController.inspect' })
        }
        try {
          const ins = await sc.inspect(会话)
          const 出 = []
          for (const e of (ins && ins.events) || []) {
            if (e.type === 'assistant/message') {
              const s = ((e.data && e.data.message && e.data.message.content) || [])
                .filter((b) => b && b.type === 'text').map((b) => b.text).join(' ').trim()
              if (s) 出.push({ 谁: '她', 文本: s })
            } else if (e.type === 'user/message') {
              const s = ((e.data && e.data.content) || [])
                .filter((b) => b && b.type === 'text').map((b) => b.text).join(' ').trim()
              if (s) 出.push({ 谁: '收', 文本: s })
            }
          }
          return 回(res, { ok: true, 会话, 条: 出.slice(-条数) })
        } catch (e) {
          return 回(res, { ok: false, 说: '读不到：' + String((e && e.message) || e) })
        }
      }

      // 建一个角色会话并直接拉进群（省得手动点）
      if (p === `${路由前缀}/create` && req.method === 'POST') {
        const 来 = await 读体(req)
        const 名字 = String(来.名字 || '角色').trim().slice(0, 20) || '角色'
        const sc = ctx.get && ctx.get('sessionController')
        if (!sc || typeof sc.create !== 'function') {
          return 回(res, { ok: false, 说: '这个部署没有 sessionController.create，只能在侧栏手动建' })
        }
        try {
          const r = await sc.create({})
          const id = String((r && (r.sessionId || r.id)) || '')
          if (!id) return 回(res, { ok: false, 说: '建了但没拿到会话 id' })
          try { if (typeof sc.rename === 'function') await sc.rename({ sessionId: id, title: 名字 }) } catch {}
          try { if (typeof sc.resolveAgent === 'function') await sc.resolveAgent(id) } catch {}
          const cfg = 读配置()
          if (!cfg.成员.some((m) => 会话键(m.id) === 会话键(id))) {
            cfg.成员.push({ id, 名字 })
            写配置(cfg)
            记账(`建了会话「${名字}」(${id}) 并加进群`)
          }
          return 回(res, { ok: true, 会话: id, 说: '建好了；如果它还没"活着"，在侧栏点开一次' })
        } catch (e) {
          return 回(res, { ok: false, 说: '建会话失败：' + String((e && e.message) || e) })
        }
      }

      // 手动让某个会话说一句（用来开场、或测试）
      if (p === `${路由前缀}/say` && req.method === 'POST') {
        const 来 = await 读体(req)
        const 目标 = String(来.会话 || 来.id || '')
        const 话 = String(来.话 || 来.text || '').trim()
        if (!目标 || !话) return 回(res, { ok: false, 说: '要 会话 和 话' })
        const agent = 找agent(目标)
        if (!agent) return 回(res, { ok: false, 说: '那个会话没活着' })
        await agent.followup({ id: randomUUID(), role: 'user', content: [{ type: 'text', text: 话 }], source: { kind: 'group-chat' } })
        return 回(res, { ok: true, 说: '送进去了，它会照常开一轮' })
      }

      return 回(res, { ok: false, 说: '没有这个路由' }, 404)
    },
  }), 'group-chat: 路由')

  return { 记账 }
}
