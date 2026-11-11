# mihomo 安装与适配记录（旧世界 / abi1）

> 机器：Loongnix GNU/Linux 20 (DaoXiangHu) / loongarch64 / KDE Plasma (X11)
> 记录时间：2026-11-10 ~ 2026-11-11
> 相关文档：[USAGE.md](./USAGE.md)（日常使用手册） · [README.md](./README.md)（本目录总览）
>
> ⚠️ **本文是旧世界机器（Loongnix 20 / 4.19 内核 / glibc 2.28）的记录，结论是"必须 abi1"。**
> 新世界机器（Loongnix 25 / 6.6 内核 / glibc 2.41）的适配记录见
> [ADAPTATION-ABI2.md](./ADAPTATION-ABI2.md) —— 那台机器上用的是 **abi2**。
> 部署包现已改为自动判定 ABI，本文的"abi2 段错误"仅对旧世界成立。

---

## 一、摘要

本机为**龙芯 LoongArch64** 架构，无法使用原版 Clash（仅发布 x86_64 / arm64）。
最终选用 **mihomo**（Clash.Meta 的继任者，官方唯一发布 `linux-loong64` 构建的 Clash 系内核）。

安装分两个阶段：

| 阶段 | 时间 | 内容 |
|---|---|---|
| 第一阶段 | 2026-11-10 16:50 起 | 下载核心、解决 ABI 段错误、写配置、首次跑通 |
| 第二阶段 | 2026-11-11 09:20 起 | 图形面板、服务化、订阅链路、脚本工具、文档 |

**所有二进制均来自官方开源仓库 Releases，未使用任何第三方镜像、修改版或破解包，
SHA256 已与官方 digest 逐一比对一致。**

---

## 二、来源与完整性校验

### 2.1 mihomo 核心

| 项目 | 值 |
|---|---|
| 仓库 | https://github.com/MetaCubeX/mihomo （**GPL-3.0**，见 `Meta` 分支 LICENSE） |
| 版本 | v1.19.33（发布于 2026-10-21） |
| 资产 | `mihomo-linux-loong64-abi1-v1.19.33.gz` |
| 下载 URL | `https://github.com/MetaCubeX/mihomo/releases/download/v1.19.33/mihomo-linux-loong64-abi1-v1.19.33.gz` |
| 官方 digest | `sha256:92b6049b661a23dd28669de5f451fd4c0a87388013684c3af9c3628d4551e77a` |
| 源码分支 | `Meta`（commit `0455d0d28c…`，Go 源码） |
| 本机安装位置 | `~/.local/bin/mihomo`（58,851,454 字节） |
| 安装时间 | 2026-11-10 17:16:43 |

**完整性验证（2026-11-11 重新下载官方原件比对）：**

```
官方 .gz 的 sha256        : 92b6049b661a23dd28669de5f451fd4c0a87388013684c3af9c3628d4551e77a
GitHub API 公布的 digest  : 92b6049b661a23dd28669de5f451fd4c0a87388013684c3af9c3628d4551e77a   ✅ 一致
解压后官方原件 sha256      : 763642918a435eb368e0ea10354df90af834c9f33a4bb785780b1b979998532b
本机 ~/.local/bin/mihomo   : 763642918a435eb368e0ea10354df90af834c9f33a4bb785780b1b979998532b   ✅ 完全一致
```

> 结论：本机核心与官方发布物**逐字节相同**，未经任何本地修改或重新编译。

构建信息：`Mihomo Meta v1.19.33 linux loong64 with go1.26.0`（tags: `with_gvisor`），
ELF 64-bit LSB，LoongArch-64，静态链接。

**版本更新**：截至 2026-11-11 15:30，官方已发布 **v1.19.34**（本机为 v1.19.33）。
升级方式与首次安装相同，注意仍须选 **abi1** 变体：

```bash
wget https://github.com/MetaCubeX/mihomo/releases/latest/download/mihomo-linux-loong64-abi1-*.gz
gunzip -f mihomo-linux-loong64-abi1-*.gz
install -m 755 mihomo-linux-loong64-abi1-* ~/.local/bin/mihomo   # 先停服务再覆盖
systemctl --user restart mihomo.service
```

升级后建议重跑 `mihomo-sub --test` 确认订阅与节点仍正常。

### 2.2 地理数据文件（GEOIP / GEOSITE 规则所需）

| 文件 | 仓库 | 官方大小 | 本机大小 | 匹配 |
|---|---|---|---|---|
| `country.mmdb` | MetaCubeX/meta-rules-dat | 7,621,999 | 7,621,999 | ✅ |
| `geoip.metadb` | MetaCubeX/meta-rules-dat | 8,406,197 | 8,406,197 | ✅ |
| `geosite.dat` | MetaCubeX/meta-rules-dat | 4,356,186 | 4,356,186 | ✅ |

来源 URL：

```
https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb
https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.metadb
https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat
```

本机这三个文件的 mtime 为 2026-11-10 12:16:09/10，与该 Release 的发布时间
`2026-11-10T04:16:11Z`（= 北京时间 12:16:11）完全吻合，可确认是在版本发布后随即
从官方仓库获取的。

### 2.3 图形面板（MetaCubeXD）

| 项目 | 值 |
|---|---|
| 仓库 | https://github.com/MetaCubeX/metacubexd （**MIT**，官方描述 "Mihomo Dashboard, The Official One, XD"） |
| 版本 | v1.274.6 |
| 来源 | `gh-pages` 分支 commit `e8b521589ac4294cc84608af8ad57b3e9b171285`（2026-11-09） |
| 下载 URL | `https://codeload.github.com/MetaCubeX/metacubexd/zip/refs/heads/gh-pages` |
| 部署位置 | `~/.config/mihomo/ui/`（160 个文件，8.2 MB） |

### 2.4 订阅链接

由**用户本人提供**（订阅链接含访问 token，此处不记录）。
未代理、未中转、未替换。

### 2.5 开源性结论

| 组件 | 来源 | 许可证 | 是否官方原版 |
|---|---|---|---|
| mihomo 核心 | github.com/MetaCubeX/mihomo **Releases** | GPL-3.0 | ✅ 是（SHA256 已验证） |
| geo 数据 | github.com/MetaCubeX/meta-rules-dat Releases | 同仓库 | ✅ 是（大小一致） |
| MetaCubeXD 面板 | github.com/MetaCubeX/metacubexd `gh-pages` | MIT | ✅ 是（官方 commit） |
| 订阅 | 用户自有 | 私有 | — |

### 2.6 ⚠️ 关于 MetaCubeX/mihomo 仓库的"错位"（重要避坑）

如果你今天打开 <https://github.com/MetaCubeX/mihomo>，看到的**不是**代理内核项目，
而是一个**完全无关的 Python 库**：

```
# mihomo
A simple python pydantic model ... for Honkai: Star Rail parsed data from the Mihomo API.
pip install -U git+https://github.com/KT-Yeh/mihomo.git
```

原因（上游仓库自身的状态，非本机问题）：

| 位置 | 实际内容 |
|---|---|
| 默认分支 `main` | 崩坏星穹铁道数据模型（Python，原属 `KT-Yeh/mihomo`，MIT） |
| `Meta` / `Alpha` 分支 | **Clash 核心的真实 Go 源码**（`adapter/`、`component/`、`config/`…，GPL-3.0） |
| **Releases** | **Clash 核心的预编译二进制**（127 个资产，含 `mihomo-linux-loong64-abi1-*`） |
| homepage | `https://wiki.metacubex.one`（核心的官方 wiki） |

即：**仓库默认分支被无关项目占据，但 Releases 仍是内核发布渠道**。

本机内核取自 **Releases**（而非 `main` 分支源码），并经 SHA256 与 GitHub API
官方 digest 双向校验一致，因此来源无疑义。若日后要自行编译，须切到 `Meta` 分支。

两个仓库的分工：

| 仓库 | 是什么 | 本机对应物 |
|---|---|---|
| `MetaCubeX/mihomo` | **代理内核**（Clash.Meta 继任者） | `~/.local/bin/mihomo` |
| `MetaCubeX/metacubexd` | **网页面板**（MetaCubeXD） | `~/.config/mihomo/ui/` |

---

## 三、为什么必须是 mihomo 而不是 Clash

原版 Clash（及 Clash Premium）官方 Releases **只有 x86_64 与 arm64**，无 loongarch64 构建。
实测各候选方案：

| 方案 | loongarch64 构建 | 本机实测结果 |
|---|---|---|
| Clash（原版 / Premium） | ❌ 无 | 不可用 |
| Clash Verge Rev（GUI） | ❌ 仅 x86_64 / aarch64 / i386 / armhfp | 不可用 |
| FlClash（GUI） | ❌ 无 | 不可用 |
| **mihomo abi1** | ✅ 有 | **✅ 实测可用** |
| mihomo abi2 | ✅ 有 | ❌ 段错误（SIGSEGV / exit 139） |
| sing-box 1.14.4（Rust 内核） | ✅ 有 | ❌ 段错误（exit 139） |

---

## 四、ABI 适配：abi2 段错误 → abi1 可用（旧世界）

这是本次安装最关键的坑。

**现象**：官方 `mihomo-linux-loong64-abi2-v1.19.33.gz` 下载正常（21.3 MB），
但一执行就段错误：

```
./mihomo -v
Segmentation fault (exit 139)
```

**排查过程**（2026-11-10 16:50 会话）：

1. 先确认不是网络/下载损坏 —— 文件大小与官方一致，可正常解压；
2. 区分「CPU/内核 ABI 问题」与「Go 运行时问题」：
   - 下载并测试 **sing-box**（Rust 实现，非 Go）→ 同样段错误，
     说明**不是 Go 运行时特有**，而是二进制与本机 ABI 不匹配；
   - 尝试从 `golang.google.cn` 拉 Go 1.20.14 loong64 工具链准备源码编译
     → 下载失败（exit 8），源码编译路线未走通；
3. 改试 mihomo 的另一个变体 **abi1（LP64）** → **正常运行**。

**根因判断**：本机内核为 `4.19.0-19-loongson-3`，属 LoongArch 早期原型内核
（3A5000 世代，`loongson-3`），与正式 3A6000（LA664，ABI v1.1 / ABI2）存在
ISA 与 ABI 差异。abi2 变体按正式 ABI2（LP64D）编译，在本机的早期 ABI 环境下崩溃；
abi1 变体按基础 LP64 编译，兼容性更好。

**结论**：这台旧世界机器**必须**使用 `linux-loong64-abi1` 变体。
该结论已写入 `config.yaml` 文件头注释，防止日后误换；新世界机器则相反（见 [ADAPTATION-ABI2.md](./ADAPTATION-ABI2.md)）。

### 4.1 ABI 差异的根源：Go 工具链，而非构建参数

查本仓库 `.github/workflows/build.yml` 可见，官方 CI 对 loong64 分成两个 matrix：

```yaml
- { goos: linux, goarch: loong64, output: loong64-abi1, abi: '1', ..., goversion: 'custom' }
- { goos: linux, goarch: loong64, output: loong64-abi2, abi: '2', ... }
```

对应的工具链来源**完全不同**：

| 变体 | 工具链 | 来源 |
|---|---|---|
| **abi1** | Go 1.26.0 (loongarch ABI1) | `MetaCubeX/loongarch64-golang` —— 龙芯官方工具链的镜像仓 |
| abi2 | Go 1.26 (标准 ABI2) | `MetaCubeX/go` |

构建命令本身**没有区别**（`GOARCH=loong64` + 同样的 ldflags），**ABI 完全由所用工具链决定**。
`MetaCubeX/loongarch64-golang` 的 README 写明：「The files are all from Loongson official
http://www.loongnix.cn/zh/toolchain/Golang/」。

**这带来一个易踩的坑**：

```bash
# ⚠️ 用系统自带的 go 编译 → 得到的是 ABI2 变体 → 在本机段错误
make linux-loong64        # Makefile 里就是 GOARCH=loong64 go build ...

# ✅ 必须用龙芯官方 ABI1 工具链
wget https://github.com/MetaCubeX/loongarch64-golang/releases/download/1.26.0/go1.26.0.linux-amd64-abi1.tar.gz
tar xzf go1.26.0.linux-amd64-abi1.tar.gz
export PATH="$PWD/go/bin:$PATH"
go version        # 确认为 loong64 ABI1 工具链
make linux-loong64
./bin/mihomo-linux-loong64 -v   # 必须正常输出，不能段错误
```

编译后务必**先跑 `-v` 验证不段错误**，再用它替换 `~/.local/bin/mihomo`。

---

## 五、适配改动清单

### 5.1 第一阶段（2026-11-10 16:50 会话：首次安装）

| # | 文件 / 位置 | 改动 | 原因 |
|---|---|---|---|
| 1 | `~/.local/bin/mihomo` | 安装官方 abi1 变体（58.8 MB） | 唯一实测可用的 Clash 系内核 |
| 2 | `~/.config/mihomo/config.yaml` | 新建完整配置 | DNS fake-ip、策略组、GEOIP/GEOSITE 规则 |
| 3 | `~/.config/mihomo/` | geo 数据三件套就位 | GEOIP / GEOSITE 规则依赖 |
| 4 | 进程启动方式 | `nohup mihomo -d ~/.config/mihomo &` | 临时方式，非持久化 |

### 5.2 第二阶段（2026-11-11 本次会话：服务化与可用性）

| # | 文件 / 位置 | 改动 | 原因 |
|---|---|---|---|
| 5 | `~/.config/systemd/user/mihomo.service` | **新建** systemd 用户服务，`enable` + `active` | 替代 nohup，开机/登录自启、崩溃自动重启 |
| 6 | 同上 | `StandardOutput=append:…/mihomo.log` | 用户无权读 systemd journal，日志落盘到可读位置 |
| 7 | 同上 | 移除 `AmbientCapabilities=CAP_NET_ADMIN` | 用户级服务提权会报 `status=218/CAPABILITIES`；TUN 模式本就需要 root |
| 8 | `~/.config/mihomo/ui/` | **部署** MetaCubeXD v1.274.6（160 文件） | 提供图形界面（架构无关，纯静态页） |
| 9 | `config.yaml` → `external-ui-url` | `github.com/…/archive/…zip` → `codeload.github.com/…/zip/…` | 本机 `/archive/` 打包接口不通，`codeload` 等价接口实测可用 |
| 10 | `config.yaml` → `proxy-providers.mysub.header` | **新增** Clash 伪装 UA 三连 | 机场按 UA 决定返回格式，不带 Clash UA 只给 base64，mihomo 解析不了 |
| 11 | `config.yaml` → `proxy-providers.mysub.url` | 占位符 → 用户真实订阅地址 | 使节点真正加载 |
| 12 | `~/.local/bin/mihomo-sub` | **新建**（含 `--relay`/`--show`/`--update`/`--test`） | 订阅管理；面板的 `/profiles` 接口 404 不可用 |
| 13 | `~/.local/bin/mihomo-sub-relay` | **新建** Python 中转（11 KB） | base64 订阅兜底：ss/vmess/trojan/hysteria2/vless → Clash YAML |
| 14 | `~/.config/systemd/user/mihomo-sub-relay.service` | **新建** systemd 用户服务 | 中转常驻（监听 127.0.0.1:18090） |
| 15 | `~/.local/bin/mihomo-panel` | **新建** | 一键打开面板 |
| 16 | `~/.local/bin/mihomo-status` | **新建** | 状态速查 |
| 17 | `~/.local/share/applications/mihomo-panel.desktop` | **新建** | KDE 菜单入口「Clash 面板 (mihomo)」 |
| 18 | `~/.config/mihomo/README.md` | **新建** | 日常使用手册 |
| 19 | `~/.config/mihomo/ADAPTATION.md` | **新建**（本文档） | 安装与适配记录 |

**核心二进制本身零改动**（SHA256 已验证），全部适配都在配置、服务与脚本层面。

---

## 六、关键技术决策与实测依据

### 6.1 图形界面方案：只能网页面板

- MetaCubeXD 官方 Releases **只有 `compressed-dist.tgz`**（纯网页构建），无桌面版；
- Clash Verge / Clash Verge Rev（Tauri，理论支持 loongarch64）实际只发布
  x86_64 / aarch64 / i386 / armhfp；
- 面板的「系统代理」功能依赖 `window.metacubexd` 桥接（仅桌面版注入），
  在浏览器标签页中不可用；
- 后端 `/profiles` 接口返回 **404**，面板内无法导入/切换订阅。

→ 结论：龙芯上无任何原生桌面客户端，网页面板是上限；系统代理需走 KDE 设置或环境变量。

### 6.2 订阅解析：User-Agent 伪装

机场普遍按 UA 决定返回格式，实测对比：

```
无 Clash UA  → cHJveGllczoKICAtIG5hbWU6…   (base64，mihomo 解析失败)
带 Clash UA  → proxies:                     (Clash YAML，正常解析)
```

因此在 `proxy-providers.mysub` 中固定伪装：

```yaml
header:
  User-Agent:
    - "clash.meta"
    - "ClashforWindows/0.20.39"
    - "Clash/1.10.0"
```

### 6.3 base64 兜底中转

针对无视 UA 只返 base64 的机场，`mihomo-sub-relay` 拉取后转换为 Clash YAML：

- 上游地址存于 `~/.config/mihomo/relay-upstream`（权限 600），**不写进 systemd 单元**；
- mihomo 从 `http://127.0.0.1:18090/sub` 取 YAML；
- 支持 ss / vmess / trojan / hysteria2 / vless 五种协议转换。

转换逻辑经本地模拟机场（返回 base64 的本地 HTTP 服务）端到端验证通过。

### 6.4 面板改配置不持久（重要）

实测：面板「配置」页走 `PATCH /configs`，只改**运行时内存**，不写回 `config.yaml`：

```
面板 PATCH log-level -> warning : 204
磁盘文件 log-level              : info    ← 未变
重启后运行时 log-level           : info    ← 恢复原值
```

→ 想永久生效必须编辑 `config.yaml`；面板改配置仅用于临时试验。

### 6.5 服务化方式选择

sudo 需要密码，无法无人值守安装系统级服务，故采用 **systemd 用户服务**：

- 权限 `Linger=yes`，用户服务无需登录桌面也会运行；
- 用户级服务拿不到 `CAP_NET_ADMIN`，因此 **TUN 全局透明代理模式不可用**，
  如需 TUN 必须用 root 安装官方 deb 包（见 README 第六节）。

---

## 七、验证记录

| 验证项 | 方法 | 结果 |
|---|---|---|
| 二进制来源 | 重新下载官方原件比对 SHA256 | ✅ 逐字节一致 |
| abi1 可运行 | `mihomo -v` | ✅ exit 0 |
| abi2 不可运行 | `mihomo -v` | ❌ exit 139（SIGSEGV） |
| 服务自启 | `systemctl --user is-enabled` | ✅ enabled |
| 面板可访问 | HTTP GET /ui/ | ✅ 200 MetaCubeXD |
| 控制 API | GET /version | ✅ v1.19.33 |
| 订阅加载 | GET /providers/proxies | ✅ 33 个节点 |
| 节点连通性 | GET /group/PROXY/delay | ✅ 28~29 个节点有有效延迟（随健康检查波动） |
| 代理转发 | 经 7890 访问 api.ip.sb | ✅ 出口日本大阪 / ASN 63949 |
| 墙外站点 | 经 7890 访问 google.com / youtube.com | ✅ 均可达 |
| 直连对照 | 不走代理访问 google.com | ❌ 超时（符合预期） |
| base64 中转 | 本地模拟机场 → 中转 → mihomo | ✅ 5 种协议全部正确 |
| 配置持久性 | PATCH /configs 后重启 | ⚠️ 仅运行时生效（已知限制） |

---

## 八、已知限制

1. **无 TUN 全局透明代理**（用户级服务无 `CAP_NET_ADMIN`），需 root 装系统级服务；
2. **7890 端口对局域网开放且无密码**（`allow-lan: true` + `bind-address: '*'`），
   共享网段内其他设备可借用，建议加 `authentication` 或改 `allow-lan: false`；
3. **面板配置不持久**（见 6.4）；
4. **面板的「配置档案」不可用**（后端 `/profiles` 404），订阅管理请用 `mihomo-sub`；
5. **面板「系统代理」按钮在浏览器中无效**（见 6.1），请用 KDE 设置或 `https_proxy` 环境变量；
6. **abi 约束（旧世界机）**：本机只能用 abi1。部署包现已自动判定 ABI，若日后升级到新世界系统，
   `install.sh` 会自动改选 abi2；新世界机器的记录见 [ADAPTATION-ABI2.md](./ADAPTATION-ABI2.md)。

---

## 九、复现步骤

```bash
# 1) 下载并安装核心（必须 abi1）
wget https://github.com/MetaCubeX/mihomo/releases/download/v1.19.33/mihomo-linux-loong64-abi1-v1.19.33.gz
gunzip -f mihomo-linux-loong64-abi1-v1.19.33.gz
mkdir -p ~/.local/bin && install -m 755 mihomo-linux-loong64-abi1-v1.19.33 ~/.local/bin/mihomo
~/.local/bin/mihomo -v        # 必须正常输出，不能段错误

# 2) 目录与配置
mkdir -p ~/.config/mihomo/providers
cp <本文档配套的 config.yaml> ~/.config/mihomo/config.yaml

# 3) 地理数据（官方）
cd ~/.config/mihomo
for f in country.mmdb geoip.metadb geosite.dat; do
  wget "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/$f"
done

# 4) 图形面板
mkdir -p ~/.config/mihomo/ui
wget -O /tmp/dash.zip https://codeload.github.com/MetaCubeX/metacubexd/zip/refs/heads/gh-pages
unzip -q /tmp/dash.zip -d /tmp/dash && cp -a /tmp/dash/metacubexd-gh-pages/. ~/.config/mihomo/ui/

# 5) 服务化
cp <mihomo.service> ~/.config/systemd/user/
systemctl --user daemon-reload && systemctl --user enable --now mihomo

# 6) 填订阅
mihomo-sub 'https://你的订阅链接'
```

---

## 十、文件清单

```
~/.local/bin/mihomo                            官方核心，SHA256 已验证
~/.local/bin/mihomo-panel                      打开图形面板
~/.local/bin/mihomo-sub                        订阅管理（直连/中转双模式）
~/.local/bin/mihomo-status                     状态速查
~/.local/bin/mihomo-sub-relay                  base64 → Clash YAML 中转

~/.config/mihomo/config.yaml                   主配置
~/.config/mihomo/README.md                     使用手册
~/.config/mihomo/ADAPTATION.md                 本文档
~/.config/mihomo/mihomo.log                    运行日志
~/.config/mihomo/relay.log                     中转日志
~/.config/mihomo/ui/                           MetaCubeXD 面板（160 文件）
~/.config/mihomo/providers/mysub.yaml          订阅缓存
~/.config/mihomo/country.mmdb                  GEOIP 数据
~/.config/mihomo/geoip.metadb                  GEOIP 数据
~/.config/mihomo/geosite.dat                   GEOSITE 数据

~/.config/systemd/user/mihomo.service          mihomo 用户服务
~/.config/systemd/user/mihomo-sub-relay.service 中转用户服务
~/.local/share/applications/mihomo-panel.desktop  KDE 菜单入口
```
