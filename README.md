# Claude Notify

把 Claude Code 终端的事件（每条回复、需要确认、任务完成）实时推送到 iPhone。

```
Claude Code (Mac) ─hook─▶ claude-notify.py ─HTTPS─▶ Go 服务 ─APNs─▶ iOS app
```

## 三个组件

| 目录 | 作用 |
| --- | --- |
| `hooks/` | Claude Code hook 脚本（Python）。接收 Stop / Notification / SubagentStop 事件，从 transcript 抽最后一条助手消息，POST 到服务器。 |
| `server/` | Go HTTP 服务。校验 shared secret，写历史，通过 APNs HTTP/2 推到所有注册过的 iPhone。 |
| `ios/ClaudeNotify/` | SwiftUI app。申请通知权限 → 注册 device token 到服务器 → 列表展示历史。 |

## 快速上手

### 1. Apple Developer 侧

- [新建 APNs Auth Key](https://developer.apple.com/account/resources/authkeys/list)（.p8），记下 **Key ID** 和 **Team ID**
- 新建一个 App ID，例如 `com.yourname.claudenotify`，开启 **Push Notifications** capability

### 2. 服务器

```bash
cd server
cp .env.example .env
# 编辑 .env，填 APNS_* 和一个够长的 SHARED_SECRET
go mod tidy
go run .
```

默认监听 `:8080`。本地测：

```bash
curl -X POST http://127.0.0.1:8080/v1/notify \
  -H "Authorization: Bearer $SHARED_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"user_id":"default","event":"test","title":"hello","body":"from curl"}'
```

### 3. Claude Code hook

```bash
mkdir -p ~/.claude/hooks
cp hooks/claude-notify.py ~/.claude/hooks/
chmod +x ~/.claude/hooks/claude-notify.py
```

把 `hooks/settings.example.json` 里的 `hooks` 块合并到 `~/.claude/settings.json`。然后在 shell rc 里：

```bash
export CLAUDE_NOTIFY_URL="http://127.0.0.1:8080"        # 或 Tailscale 地址
export CLAUDE_NOTIFY_SECRET="same-as-server-SHARED_SECRET"
export CLAUDE_NOTIFY_USER="default"
```

### 4. iOS app

见 [ios/SETUP.md](ios/SETUP.md)。关键点：
- Bundle ID 必须和 `APNS_BUNDLE_ID` 一致
- Info.plist 加两个字段：`CLAUDE_NOTIFY_URL`、`CLAUDE_NOTIFY_SECRET`
- **必须真机**，模拟器收不到 APNs
- 手机要能访问 Mac 上的服务器 → 最省事的是 [Tailscale](https://tailscale.com)

## 关于"所有消息"

现在钩的是 `Stop` / `Notification` / `SubagentStop`：每次 Claude 回复完一条都推。太吵就在 `settings.json` 里只留 `Notification`（需要你确认时）+ `SubagentStop`（子任务完成）。

## 后续可以做

- [ ] 多项目分组（按 cwd 聚合 threadID，iOS 已经按 session 分组了）
- [ ] 从通知里快速回复（Notification Content Extension + POST 回 Claude）
- [ ] 历史换 SQLite，加全文搜索
- [ ] 服务器部署到 fly.io / Railway
