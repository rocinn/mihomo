# 龙芯 (LoongArch64) 部署包

本目录是 **mihomo 在 LoongArch64 上的完整部署产物与适配记录**，可直接用于新机器复现。

> 目标机器：Loongnix GNU/Linux 20 (DaoXiangHu) / **loongarch64** / KDE Plasma (X11)
> 实测版本：mihomo **v1.19.33** `linux-loong64-abi1` / MetaCubeXD 面板 **v1.274.6**
> 记录时间：2026-11-10 ~ 2026-11-11

---

## 一、为什么需要这个包

原版 Clash / Clash Premium 只发布 x86_64 与 arm64，**没有 loongarch64 构建**。
Clash.Meta 的继任者 **mihomo** 是唯一提供 `linux-loong64` 的 Clash 系内核，
但有两个坑必须处理：

| 坑 | 现象 | 本包的处理 |
|---|---|---|
| **ABI 不匹配** | 官方 `abi2` 变体在本机一执行就 SIGSEGV | 改用 `abi1` 变体（见 [ADAPTATION.md §4](ADAPTATION.md)） |
| **订阅格式歧义** | 机场按 User-Agent 返回 base64，mihomo 解析失败 | 内置伪装 UA + base64 中转兜底 |

---

## 二、快速开始

```bash
# 1) 安装(会自动完成 核心 → 配置 → 面板 → 服务 → 脚本 → 桌面入口)
./install.sh

# 2) 填订阅
mihomo-sub 'https://你的订阅链接'

# 3) 打开图形面板
mihomo-panel            # 或浏览器访问 http://127.0.0.1:9090/ui/
```

或者手工执行：

```bash
# 核心(必须 abi1!)
wget https://github.com/MetaCubeX/mihomo/releases/latest/download/mihomo-linux-loong64-abi1-*.gz
gunzip -f mihomo-linux-loong64-abi1-*.gz
install -m 755 mihomo-linux-loong64-abi1-* ~/.local/bin/mihomo
~/.local/bin/mihomo -v          # ← 必须正常输出，不能段错误

# 配置目录
mkdir -p ~/.config/mihomo/providers
cp config/config.yaml ~/.config/mihomo/config.yaml

# 地理数据(GEOIP / GEOSITE 规则依赖)
for f in country.mmdb geoip.metadb geosite.dat; do
  wget "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/$f" \
    -O ~/.config/mihomo/$f
done

# 图形面板
mkdir -p ~/.config/mihomo/ui
wget -O /tmp/dash.zip https://codeload.github.com/MetaCubeX/metacubexd/zip/refs/heads/gh-pages
unzip -q /tmp/dash.zip -d /tmp/dash
cp -a /tmp/dash/metacubexd-gh-pages/. ~/.config/mihomo/ui/

# 服务化
mkdir -p ~/.config/systemd/user
cp systemd/*.service ~/.config/systemd/user/
systemctl --user daemon-reload && systemctl --user enable --now mihomo.service

# 工具脚本
mkdir -p ~/.local/bin ~/.local/share/applications
cp scripts/mihomo* ~/.local/bin/ && chmod +x ~/.local/bin/mihomo*
cp desktop/mihomo-panel.desktop ~/.local/share/applications/
```

---

## 三、目录结构

```
deploy/loongarch64/
├── README.md              ← 本文件:总览与快速开始
├── ADAPTATION.md          ← 适配全过程记录:来源溯源、SHA256 校验、ABI 排查、19 项改动、验证记录、已知限制
├── USAGE.md               ← 日常使用手册:面板在哪、订阅怎么加、系统代理怎么设、命令速查
├── install.sh             ← 一键部署脚本
├── config/
│   ├── config.yaml        ← 完整可用配置(订阅地址为占位符,需自行填写)
│   └── .gitignore         ← 防止把含 token 的本地配置提交进仓库
├── systemd/
│   ├── mihomo.service              ← 用户级服务(已用 %h 规范,跨机器可直接用)
│   └── mihomo-sub-relay.service    ← 订阅中转服务
├── scripts/
│   ├── mihomo-panel        ← 打开图形面板
│   ├── mihomo-sub          ← 订阅管理(直连/中转双模式 + 自检)
│   ├── mihomo-status       ← 状态速查
│   └── mihomo-sub-relay    ← base64 → Clash YAML 中转(Python)
└── desktop/
    └── mihomo-panel.desktop ← KDE 菜单入口「Clash 面板 (mihomo)」
```

---

## 四、本机运行实例与本目录的对应关系

| 本目录 | 本机实际位置 | 说明 |
|---|---|---|
| `config/config.yaml` | `~/.config/mihomo/config.yaml` | **线上那份含真实订阅地址**，仓库这份已脱敏 |
| `systemd/*.service` | `~/.config/systemd/user/` | 完全相同（用 `%h` 展开，与用户名无关） |
| `scripts/mihomo*` | `~/.local/bin/` | 完全相同 |
| `desktop/*.desktop` | `~/.local/share/applications/` | 仓库里是模板（`@HOME@` 占位），`install.sh` 安装时替换为实际家目录 |
| `ADAPTATION.md` / `USAGE.md` | `~/.config/mihomo/` | 同名副本，方便在机器上直接查 |
| —— | `~/.config/mihomo/ui/` | MetaCubeXD 面板（8.2 MB / 160 文件，未入库） |
| —— | `~/.config/mihomo/{country.mmdb,geoip.metadb,geosite.dat}` | 地理数据（未入库） |

> **本目录是"来源"，机器上的副本是"运行实例"。** 两者同步更新，机器侧改动请回写本目录。

### ⚠️ 关于订阅地址

真实订阅链接**含访问 token**，只存在于 `~/.config/mihomo/config.yaml`
与 `~/.config/mihomo/relay-upstream`（权限 600），**两者都不会进仓库**：

- 仓库里的 `config/config.yaml` 用占位符 `https://example.com/your-subscription-link`
- `config/.gitignore` 已排除 `config.local.yaml` 与 `relay-upstream`
- 若要提交本机配置，请先确认没有 token 残留

---

## 五、验证结果摘要

| 验证项 | 结果 |
|---|---|
| 二进制来源 | 与官方 Releases **SHA256 逐字节一致**（未改一字） |
| abi1 / abi2 | abi1 ✅ 正常运行 / abi2 ❌ SIGSEGV |
| 订阅加载 | 33 节点，`GET /providers/proxies` 验证 |
| 节点连通 | 28~29 节点有有效延迟 |
| 代理转发 | 出口日本大阪 ASN 63949 |
| 墙外站点 | Google / YouTube 经代理可达，直连超时 |
| 面板 | `http://127.0.0.1:9090/ui/` 返回 200 |
| base64 中转 | 本地模拟机场端到端验证，5 种协议全对 |

详见 [ADAPTATION.md 第七章](ADAPTATION.md)。

---

## 六、已知限制

1. **无 TUN 全局透明代理** —— 用户级 systemd 拿不到 `CAP_NET_ADMIN`，
   需 root 安装系统级服务（见 [USAGE.md](USAGE.md) 第六章）；
2. **7890 端口对局域网开放且无密码** —— `allow-lan: true` + `bind-address: '*'`，
   建议按 [USAGE.md 第五章](USAGE.md) 收紧；
3. **面板改配置不持久** —— 面板走 `PATCH /configs` 只改运行时，不写回 `config.yaml`；
4. **面板「配置档案」页不可用** —— 后端 `/profiles` 返回 404，订阅管理请用 `mihomo-sub`；
5. **面板「系统代理」按钮在浏览器中无效** —— 依赖桌面端桥接，龙芯无桌面版；
6. **必须用 abi1** —— 见 [ADAPTATION.md §4.1](ADAPTATION.md)，
   用系统自带 Go 编译会得到会崩的 abi2。

---

## 七、文档索引

| 文档 | 内容 |
|---|---|
| [ADAPTATION.md](ADAPTATION.md) | 来源溯源与 SHA256 校验、ABI 段错误完整排查、19 项改动清单、技术决策依据、验证记录、复现步骤 |
| [USAGE.md](USAGE.md) | 面板页面地图、订阅两种模式、系统代理设置、TUN 模式、常用命令、常见问题 |

---

## 八、关于上游仓库的"错位"（避坑）

若要从源码编译，注意 `MetaCubeX/mihomo` 仓库的**默认分支 `main` 现在是一个无关的
Python 项目**（崩坏星穹铁道数据模型），Clash 核心的真实 Go 源码在 **`Meta` / `Alpha`
分支**，而**内核二进制发布在 Releases**。

```bash
# ✅ 必须指定分支，否则克隆到的是星铁那个库
git clone -b Meta https://github.com/MetaCubeX/mihomo.git

# ❌ 不指定 → 拿到无关的 Python 项目
git clone https://github.com/MetaCubeX/mihomo.git
```

且编译时仍需**龙芯官方 ABI1 工具链**，否则产出的是在本机崩溃的 abi2 变体。
详见 [ADAPTATION.md §2.6 与 §4.1](ADAPTATION.md)。
