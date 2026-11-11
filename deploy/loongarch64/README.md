# 龙芯 (LoongArch64) 部署包

本目录是 **mihomo 在 LoongArch64 上的完整部署产物与适配记录**，可直接用于新机器复现。

> 目标机器（均已实测）：
> - 旧世界：Loongnix GNU/Linux 20 (DaoXiangHu) / 3A6000 / 内核 4.19 / **abi1**
> - 新世界：Loongnix GNU/Linux 25 / 3B6000 / 内核 6.6 / **abi2**
>
> 实测版本：mihomo **v1.19.34**（`linux-loong64-abi1` / `abi2` 双变体）/ MetaCubeXD 面板
> 记录时间：2026-11-10 ~ 2026-11-11

---

## 一、为什么需要这个包

原版 Clash / Clash Premium 只发布 x86_64 与 arm64，**没有 loongarch64 构建**。
Clash.Meta 的继任者 **mihomo** 是唯一提供 `linux-loong64` 的 Clash 系内核，但有两个坑必须处理：

| 坑 | 现象 | 本包的处理 |
|---|---|---|
| **ABI 双世界** | 官方同时发 `abi1` / `abi2`：旧世界（Loongnix 20）跑 abi2 会 `SIGSEGV`；新世界（Loongnix 25）优先 abi2 | `install.sh` 自动判定：glibc 判世界 → 实测二进制能否运行 → 不行自动换变体 |
| **订阅格式歧义** | 机场按 User-Agent 返回 base64，mihomo 解析失败 | 内置伪装 UA + base64 中转兜底（无 PyYAML 也能跑） |
| **GitHub 直连慢** | 本机直连 Releases 约 3.7 KB/s | 直连限时 30 s，失败自动走镜像；镜像内容仍按官方 SHA256 校验 |
| **DNS fallback 被阻断** | 1.1.1.1 / 8.8.8.8 在本网络不可达，GEOIP 判定每次等约 10 s | `config.yaml` 的 fallback 改用可达的 `doh.pub` / `tls://223.5.5.5`（见 ADAPTATION-ABI2 §4.3） |
| **浏览器直连** | lbrowser（Chromium）不读环境变量、也没配代理，访问 GitHub 直接走裸连 | 需手动设一次 KDE 系统代理（系统设置 → 网络 → 网络代理，见 [USAGE.md §六](./USAGE.md)）；Chromium 启动时读取，改完重开浏览器生效 |

---

## 二、快速开始

```bash
# 0) 只看环境，不改动任何东西
./install.sh --check

# 1) 安装（自动完成 核心 → 配置 → 面板 → 服务 → 脚本 → 桌面入口）
./install.sh

# 2) 填订阅
mihomo-sub 'https://你的订阅链接'

# 3) 打开图形面板
mihomo-panel            # 或浏览器访问 http://127.0.0.1:9090/ui/
```

需要强制 ABI 变体时：

```bash
./install.sh --abi abi2          # abi1 | abi2
MIHOMO_ABI=abi1 ./install.sh     # 等价的环境变量写法
```

已装变体与指定值不一致时会重新下载安装（约 21 MB）；一致则跳过。
不强制时脚本保持幂等，已装好能跑就不重复下载。

> 网络取不到 GitHub API 时无法自动解析 `latest`，此时显式指定版本即可照常安装
> （会跳过 SHA256 校验）：`MIHOMO_VERSION=v1.19.34 ./install.sh`。

或者手工执行：

```bash
# 核心（变体按系统选：旧世界 abi1 / 新世界 abi2）
wget https://github.com/MetaCubeX/mihomo/releases/latest/download/mihomo-linux-loong64-abi2-*.gz
gunzip -f mihomo-linux-loong64-abi2-*.gz
install -m 755 mihomo-linux-loong64-abi2-* ~/.local/bin/mihomo
~/.local/bin/mihomo -v          # ← 必须正常输出，不能段错误

# 配置目录
mkdir -p ~/.config/mihomo/providers
cp config/config.yaml ~/.config/mihomo/config.yaml

# 地理数据（GEOIP / GEOSITE 规则依赖）
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
├── README.md              ← 本文件：总览与快速开始
├── ADAPTATION.md          ← 旧世界机器（Loongnix 20 / abi1）适配记录
├── ADAPTATION-ABI2.md     ← 新世界机器（Loongnix 25 / abi2）适配记录
├── USAGE.md               ← 日常使用手册：面板、订阅、系统代理、命令速查
├── install.sh             ← 一键部署脚本（自动判定 abi1/abi2）
├── config/
│   ├── config.yaml        ← 完整可用配置（订阅地址为占位符，需自行填写）
│   └── .gitignore         ← 防止把含 token 的本地配置提交进仓库
├── systemd/
│   ├── mihomo.service              ← 用户级服务（%h 展开，跨机器可直接用）
│   └── mihomo-sub-relay.service    ← 订阅中转服务
├── scripts/
│   ├── mihomo-panel        ← 打开图形面板
│   ├── mihomo-sub          ← 订阅管理（直连/中转双模式 + 自检）
│   ├── mihomo-status       ← 状态速查（含 ABI 行）
│   └── mihomo-sub-relay    ← base64 → Clash YAML 中转（PyYAML 可选）
└── desktop/
    └── mihomo-panel.desktop ← KDE 菜单入口「Clash 面板 (mihomo)」
```

---

## 四、本机运行实例与本目录的对应关系

| 本目录 | 机器上实际位置 | 说明 |
|---|---|---|
| `config/config.yaml` | `~/.config/mihomo/config.yaml` | **线上那份含真实订阅地址**，仓库这份已脱敏 |
| `systemd/*.service` | `~/.config/systemd/user/` | 完全相同（用 `%h` 展开，与用户名无关） |
| `scripts/mihomo*` | `~/.local/bin/` | 完全相同 |
| `desktop/*.desktop` | `~/.local/share/applications/` | 仓库里是模板（`@HOME@` 占位），`install.sh` 安装时替换为实际家目录 |
| `ADAPTATION*.md` / `USAGE.md` | `~/.config/mihomo/` | 可复制过去，方便在机器上直接查 |
| —— | `~/.config/mihomo/abi` | `install.sh` 安装/更换变体时写入的判定结果（`abi1` / `abi2`） |
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

| 验证项 | 旧世界（3A6000 / Loongnix 20） | 新世界（3B6000 / Loongnix 25） |
|---|---|---|
| 二进制来源 | 与官方 Releases **SHA256 逐字节一致** | 同左（`a8d8a080…`） |
| ABI 可用性 | abi1 ✅ / abi2 ❌ SIGSEGV | **abi2 ✅** / abi1 ✅（兼容，不采用） |
| 核心运行 | `mihomo -v` exit 0 | ✅ `v1.19.34` / `go1.26.11` |
| 用户服务 | ✅ active | ✅ active（mihomo + 中转） |
| 面板 | 200 | ✅ 200（160 文件） |
| 订阅加载 | 33 节点 | ✅ 33 节点 |
| 节点连通 | 28~29 节点有有效延迟 | ✅ 32/32 有有效延迟 |
| 代理转发 | 出口日本大阪 | ✅ 出口新加坡（IPv6） |
| 墙外站点 | Google / YouTube 经代理可达 | ✅ Google 204 / YouTube 200 / GitHub 200 |
| base64 中转 | 5 种协议端到端验证 | ✅ 无 PyYAML 下 3 节点，mihomo 正常解析 |
| DNS / 代理端口 | —— | ✅ `doh.pub` fallback 后 `api.ip.sb` 0.38 s / baidu 0.06 s（经 7890） |

> 表中「——」表示该机器上没做这项验证，不是失败。

详见 [ADAPTATION.md](./ADAPTATION.md)（旧世界）与 [ADAPTATION-ABI2.md](./ADAPTATION-ABI2.md)（新世界）。

---

## 六、已知限制

1. **TUN 全局透明代理需要 root** —— 用户级 systemd 拿不到 `CAP_NET_ADMIN`，
   需系统级服务（见 [USAGE.md](./USAGE.md) 第六章）；
2. **7890 端口对局域网开放且无密码** —— `allow-lan: true` + `bind-address: '*'`，
   建议按 [USAGE.md 第五章](./USAGE.md) 收紧；
3. **面板改配置不持久** —— 面板走 `PATCH /configs` 只改运行时，不写回 `config.yaml`；
4. **面板「配置档案」页不可用** —— 后端 `/profiles` 返回 404，订阅管理请用 `mihomo-sub`；
5. **面板「系统代理」按钮在浏览器中无效** —— 依赖桌面端桥接，龙芯无桌面版；
6. **linger 影响自启范围** —— 未开 linger 时，注销桌面后用户服务会停止；
   常驻需 `sudo loginctl enable-linger $USER`；
7. **ABI 由脚本自动判定** —— 不想依赖自动判定时用 `--abi` / `MIHOMO_ABI` 强制；
   强制值与已装变体不一致会重新下载（旧版安装没留 `abi` 记录时，用 `--abi` 跑一次即可补记）。

---

## 七、文档索引

| 文档 | 内容 |
|---|---|
| [ADAPTATION.md](./ADAPTATION.md) | 旧世界（Loongnix 20）来源溯源、SHA256 校验、abi2 段错误排查、19 项改动、验证记录 |
| [ADAPTATION-ABI2.md](./ADAPTATION-ABI2.md) | 新世界（Loongnix 25）ABI 判定、镜像与校验、12 项改动、DNS fallback 与浏览器代理实测、验证记录、复现步骤 |
| [USAGE.md](./USAGE.md) | 面板页面地图、订阅两种模式、系统代理设置、TUN 模式、常用命令、常见问题 |

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

自行编译时 ABI 由**工具链**决定（构建参数相同），见 `.github/workflows/build.yml`：

| 目标 | 工具链 |
|---|---|
| abi1（旧世界） | `MetaCubeX/loongarch64-golang` 的 Go 1.26.0（龙芯官方 ABI1 工具链） |
| abi2（新世界） | 上游标准 Go 1.26（`MetaCubeX/go`） |

用错工具链，产物会在目标机器上直接段错误。详见 [ADAPTATION.md §4.1](./ADAPTATION.md)。
