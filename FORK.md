# Fork 说明 — `rust-v0.157.1-lock1`

## 版本与冻结策略

- **基于**：openai/codex 的 `rust-v0.157.1` tag（commit `3665039`）
- **fork tag**：`rust-v0.157.1-lock1`
- ⚠️ **本 fork 冻结在 rust-v0.157.1，不跟随官方更新。**
  - 不要点 GitHub 上的 "Sync fork" 按钮（它会拉上游 main 进来，与分支冲突）
  - 不要把上游 main / 新 tag merge 或 rebase 进 `lock-proxy-timezone` 分支
  - 唯一可信源：本仓库的 `lock-proxy-timezone` 分支 + `rust-v0.157.1-lock1` tag
  - 网络层版本号（遥测 `codex_rs_version`、请求头）刻意保持官方一致（`0.157.1`），
    仅本地 `codex --version` 显示 `0.157.1-lock1` 用于区分

## 行为说明（与官方的差异）

1. **代理锁定**：所有非回环（非 localhost/127.0.0.1/::1）流量固定走 lock 文件里的代理，
   不读 Windows 系统代理、不读 `HTTP_PROXY` 等环境变量、**不回退直连**（代理挂了就失败）。
   覆盖推理请求、bootstrap、登录、遥测、MCP HTTP。
2. **时区锁定**：发给模型的 `<environment>` 时区/日期来自 lock 文件（`America/Los_Angeles`，
   含美国夏令时规则），不读系统时区。上传的时间戳均为 UTC epoch，本身无时区语义。
3. **webview CSP 全锁**：TUI 内联可视化 WebView 禁止一切远程 CDN 加载（仅 blob:/data:）。

## 配置文件

查找顺序（`codex-rs/http-client/src/lock_config.rs`）：

1. `$CODEX_LOCK_CONFIG` 指定的任意路径
2. `$CODEX_HOME/lock.toml`
3. `~/.codex/lock.toml`（默认；Windows 为 `C:\Users\<你>\.codex\lock.toml`）

```toml
proxy = "http://127.0.0.1:10809"      # 仅支持 HTTP 代理
timezone = "America/Los_Angeles"      # 日期支持 LA(夏令时)/上海/东京/伦敦等，未知按 UTC
```

缺省值即上述默认（文件不存在也生效）。

**紧急关闭**：`CODEX_LOCK_DISABLE=1` 恢复官方网络/时区行为（`justfile` 的 `test`
recipe 已内置此变量，所以 `just test` 跑的是上游原始逻辑）。

## 改动文件清单（相对 rust-v0.157.1）

| 文件 | 改动 |
|---|---|
| `codex-rs/http-client/src/lock_config.rs` | 新增：lock.toml 读取与默认值 |
| `codex-rs/http-client/src/lock_config_tests.rs` | 新增：解析器单测 |
| `codex-rs/http-client/src/outbound_proxy.rs` | 锁定路由 + 3 个拦截点 + legacy 注入 |
| `codex-rs/http-client/src/outbound_proxy_tests.rs` | locked_proxy_route 单测 |
| `codex-rs/http-client/src/client_builder.rs` | transport-default 构建也走锁定代理 |
| `codex-rs/http-client/src/lib.rs` | 模块注册与导出 |
| `codex-rs/core/src/session/turn_context.rs` | 时区/日期改为 lock 文件驱动 |
| `codex-rs/core/src/session/mod.rs` | 移除无用 chrono 导入 |
| `codex-rs/tui/src/inline_visualization/viewer.rs` | CSP 去除全部远程源 |
| `codex-rs/tui/src/snapshots/...viewer_document_contract.snap` | 快照随 CSP 更新 |
| `justfile` | test recipe 注入 `CODEX_LOCK_DISABLE=1` |
| `codex-rs/cli/src/main.rs` | `--version` 显示 `-lock1` 后缀（仅本地） |
| `codex-rs/Cargo.lock` | 上游 tag 遗留的版本号规范化（0.0.0→0.157.1） |

## 构建与测试

```powershell
cd codex-rs
cargo build --release -p codex-cli     # 产物: target/release/codex.exe
just test -p codex-http-client         # 或 -p codex-core / -p codex-tui
```

已知本机（Windows）预存失败（原版 tag 同样失败，非本 fork 引入）：
`tls_fallback_tests` 5 个（SChannel）、`suite::rmcp_client` environment 3 个（wiremock）。

## 如果某天确实要换新版本（不推荐）

手动操作，绝不用 Sync fork：

```bash
git remote add upstream https://github.com/openai/codex.git
git fetch upstream --tags
git checkout -b lock-proxy-timezone-vNEW rust-vNEW.x
# 然后按上表逐文件重放改动（cherry-pick 5c94a51 436e1ee 可能冲突，冲突点集中
# 在 outbound_proxy.rs / client_builder.rs / turn_context.rs / viewer.rs / justfile）
```
