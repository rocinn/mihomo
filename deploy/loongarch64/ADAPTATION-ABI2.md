# 新世界（abi2）适配记录 —— 3B6000 / Loongnix 25

> 机器：**Loongnix GNU/Linux 25 (loongnix)** / loongarch64 / KDE Plasma (X11)
> 记录时间：2026-11-11
> 对照文档：[ADAPTATION.md](./ADAPTATION.md) —— 旧世界机器（3A6000 NUC / Loongnix 20 / 4.19 内核 / 必须 abi1）
> 本目录总览：[README.md](./README.md) · 日常使用：[USAGE.md](./USAGE.md)

---

## 一、摘要

同一套 `deploy/loongarch64/` 部署包，在两代龙芯机器上得到**相反的 ABI 结论**：

| 机器 | 系统 | 内核 | glibc | 可用的 ABI |
|---|---|---|---|---|
| 3A6000 NUC（旧记录） | Loongnix 20 (DaoXiangHu) | 4.19 | 2.28 | **abi1**（abi2 段错误） |
| **3B6000（本文）** | **Loongnix 25** | **6.6.52** | **2.41** | **abi2**（abi1 也能跑，但优先 abi2） |

所以部署包不再写死变体，改为**自动判定**：

1. 用 glibc 版本判断世界：`>= 2.36` 为新世界，优先 `abi2`；否则优先 `abi1`；
2. 下载后先 `mihomo -v` 实测，跑不起来就自动换另一个变体（判据是"能运行"，不是猜）；
3. 二进制必须通过 `api.github.com` 公布的官方 SHA256 校验才安装；
4. 判定结果写入 `~/.config/mihomo/abi`，`mihomo-status` 会显示。

本机最终结果：**mihomo v1.19.34 / linux loong64 / abi2**。用户级 systemd 服务、7890 代理端口、
9090 控制 API、MetaCubeXD 面板、订阅中转均已就绪并通过自检。

---

## 二、环境指纹

| 项目 | 值 |
|---|---|
| 主机名 | `3B6000` |
| 发行版 | Loongnix GNU/Linux 25（`VERSION_ID="25"`, `loongnix-stable`） |
| 内核 | `6.6.52-loong64`（Loongnix 6.6.52-1.11，构建于 2026-07-23） |
| glibc | 2.41 |
| 编译器 | gcc 14.2.0 (Loongnix 14.2.0-19.lnd.1+b1) |
| 桌面 | KDE Plasma / X11 |
| systemd 用户实例 | 可用（`is-system-running` 报 `degraded`，但 `systemctl --user status` 正常） |
| linger | **未开启**（`Linger=no`） |
| Python | 3.13，**未安装 PyYAML** |

---

## 三、ABI 判定：新世界 vs 旧世界

LoongArch 目前存在两套用户态 ABI：

| | 旧世界 | 新世界 |
|---|---|---|
| 代表系统 | Loongnix 20、多数 3A5000/3A6000 出厂系统 | Loongnix 25、Debian/Fedora 等主线发行版 |
| glibc | 2.28（龙芯维护分支） | >= 2.36（上游主线） |
| 内核 | 4.19 / 5.x | 6.x |
| mihomo 变体 | `linux-loong64-abi1` | `linux-loong64-abi2` |

### 3.1 实测证据

在 `v1.19.34` 上把两个变体都下载到本机实测（SHA256 均与官方 digest 一致）：

| 变体 | 构建串（`mihomo -v`） | 本机结果 |
|---|---|---|
| `abi1` | `Mihomo Meta v1.19.34 linux loong64 with go1.26.0` | ✅ exit 0 |
| `abi2` | `Mihomo Meta v1.19.34 linux loong64 with go1.26.11` | ✅ exit 0（本文采用） |

> 构建串里的 Go 版本可以作为变体标记：abi1 用龙芯官方 ABI1 工具链（`MetaCubeX/loongarch64-golang`，
> Go 1.26.0），abi2 用上游 Go 1.26.11。

### 3.2 为什么不能只看"能不能跑"

两个变体都能跑——但这不代表可以随便选，也不代表旧世界能跑 abi2：

- **旧世界**：abi2 会 `SIGSEGV`（已由 3A6000 那台机器实测，见 [ADAPTATION.md §4](./ADAPTATION.md)）；
- **新世界**：静态链接的 Go 二进制 abi1 也通常能跑（mihomo 正是静态链接、纯 Go），
  但它不是为本机工具链构建的，没有理由优先；
- 因此判据顺序是：**先判世界 → 选首选变体 → 实测能否运行 → 不行再回退**。

`install.sh` 的实现（`abi_order()` / `install_core()`）：

```text
glibc >= 2.36 ? abi2,abi1 : abi1,abi2
逐个尝试：下载 → 官方 SHA256 校验 → mihomo -v 实测 → 通过即安装并写 ~/.config/mihomo/abi
```

也可以用 `./install.sh --abi abi1|abi2` 或 `MIHOMO_ABI=abi2 ./install.sh` 强制指定。

两个行为细节（2026-11-11 修订，均已用假 HOME + 桩下载做离线回归）：

- **幂等**：不带 `--abi` 时，已装且能跑的核不会再下载，也不会改写 `abi` 记录；
- **强制即重装**：带了 `--abi` 且与 `abi` 记录不一致时会重新下载安装该变体——
  旧版安装没留 `abi` 记录时，跑一次 `--abi` 就能补记并校准。

---

## 四、网络与来源校验

### 4.1 直连不可用 → 镜像只做传输

本机直连 GitHub Releases 实测约 **3.7 KB/s**（615 KB / 167 s），21 MB 的内核包要下几个小时。
`gh-proxy.com` 镜像同一文件 **2.5 s** 完成。

部署包的策略：

1. 先直连，`timeout 30` 限时；失败或过慢自动改走镜像（`MIHOMO_GH_PROXY`，默认 `https://gh-proxy.com`）；
2. **镜像只负责传输**：安装前一律用 `api.github.com` 的官方 asset digest 做 SHA256 比对，
   不一致立即删除并中止；
3. API 也不可达时会在输出里明确警告"跳过 SHA256 校验"，不会静默放行；
   此时若显式给了 `MIHOMO_VERSION`，脚本按该版本号照常下载安装；
   没给版本号则无法确定 `latest`，会中止并提示补一个版本号。

### 4.2 本次校验记录（2026-11-11）

| 文件 | 大小 | 官方 SHA256 | 本机 |
|---|---|---|---|
| `mihomo-linux-loong64-abi2-v1.19.34.gz` | 21,241,310 | `011c4f38152a976ad79cb0fec07444cbc725089a4a3bb71fa268f4639db9d751` | ✅ |
| `mihomo-linux-loong64-abi1-v1.19.34.gz` | 21,623,099 | `3d768e7483a9390160ec04baa0b73689ed317b0f3384dbb8c113ec31f092ec87` | ✅ |
| `country.mmdb` | 7,621,999 | `c0c6ea5661a3167abb24bbbaf629605aa3856c425384cbf2897c5a0f41027663` | ✅ |
| `geoip.metadb` | 8,406,197 | `1772d37f4f541f86de198ba9e51131dcb223cf4dec7a2a967d636f827ff150d6` | ✅ |
| `geosite.dat` | 4,356,285 | `da712b401ea6f4fdb45983e7a3458332decb85c244307b443df3e11feb4af366` | ✅ |

安装后 `~/.local/bin/mihomo`（59,048,062 字节）的 SHA256 为
`a8d8a080c17f8e833e053040daebf9daa76463b6310dddf50766133cea484440`，与解压后的官方文件一致。

面板（MetaCubeXD `gh-pages`）官方未发布 digest，只能校验传输完整性（zip 解压正常、160 个文件）。

### 4.3 DNS fallback 在本网络不可达

原配置的 `fallback` 是 `tls://1.1.1.1` / `tls://8.8.8.8`。本机实测：

| 端点 | 结果 |
|---|---|
| `tls://1.1.1.1:853` | ❌ 不可达 |
| `tls://8.8.8.8:853` | ❌ 不可达 |
| `https://dns.google` / `https://cloudflare-dns.com` | ❌ 超时 |
| `https://doh.pub/dns-query` | ✅ 200 |
| `https://dns.alidns.com` | ✅ 200 |
| `tls://223.5.5.5:853` | ✅ 可握手 |

fallback 不可达的直接后果：每次 `GEOIP` 规则判定都要等满超时，表现为
"经 7890 访问境外站点要卡 ~10 s 甚至直接报 502"，日志里是
`dns resolve failed: context deadline exceeded`。

因此把 `config.yaml` 的 fallback 改为可达的国内加密 DNS：

```yaml
  fallback:
    - https://doh.pub/dns-query
    - tls://223.5.5.5
```

改后实测：`GET /dns/query?name=api.ip.sb` 立即返回，经 7890 访问 `http://api.ip.sb/ip`
从"10 s 超时"变为 **200 / 0.38 s**。若你的网络能直连境外 DNS，可换回 1.1.1.1 / 8.8.8.8。

---

## 五、适配改动清单（本机）

| # | 文件 | 改动 | 原因 |
|---|---|---|---|
| 1 | `install.sh` | `install_core` 自动判定 ABI：glibc 判世界 + `-v` 实测 + 失败回退，结果写 `~/.config/mihomo/abi` | 新旧世界结论相反，写死任一变体都会在另一代机器上翻车 |
| 2 | `install.sh` | 新增 `--abi abi1\|abi2` 与 `MIHOMO_ABI`；与已装变体不一致时重装，一致时跳过 | 排查/复现时可强制变体；也用于给旧版安装补记 `abi` |
| 3 | `install.sh` | 直连 30 s 超时后自动走镜像；下载物按官方 SHA256 校验 | 本机 GitHub 直连基本不可用；镜像需可验证 |
| 4 | `install.sh` | systemd 可用性判据改为 `systemctl --user status` | 本机 `is-system-running` 返回 `degraded`（exit 1），旧判据会误判"不可用"并跳过服务安装 |
| 5 | `install.sh` | 面板解包改为定位 `index.html` 所在目录 | 压缩包顶层目录名随源/镜像变化，旧代码写死 `$UI_REPO-$UI_BRANCH` 在本机直接 `cp` 失败 |
| 6 | `install.sh` | 增加 PyYAML 探测与 linger 提示 | 本机无 PyYAML、linger=no，安装时就该说清楚 |
| 7 | `config/config.yaml` | 头部注释改为 ABI 中立说明 | 配置模板不再声称"必须 abi1" |
| 8 | `scripts/mihomo-sub-relay` | PyYAML 改为可选：无 PyYAML 时 base64 订阅输出 JSON（合法 YAML）、已是 YAML 则原样透传 | 本机没有 python3-yaml，且无 root 无法 `apt install` |
| 9 | `scripts/mihomo-status` | 增加 ABI / 系统行 | 一眼看出当前用的是哪个变体 |
| 10 | `config/config.yaml` | `fallback` 从 1.1.1.1/8.8.8.8 改为 `doh.pub` + `tls://223.5.5.5` | 本机网络下境外 DNS 全不可达，GEOIP 判定每次等 10 s（见 §4.3） |
| 11 | 文档 | 新增本文；README/USAGE/ADAPTATION 补充新世界说明 | 两台机器的记录不能互相矛盾 |
| 12 | `~/.config/kioslaverc` | 写入 KDE 系统代理 `127.0.0.1:7890`（HTTP/HTTPS/SOCKS + NoProxyFor 内网） | 本机浏览器 lbrowser（Chromium）启动时读 kioslaverc；不配则浏览器完全直连，GitHub 慢到不可用 |

**核心二进制零改动**（只做来源校验与安装），全部适配都在判定逻辑、配置、服务与脚本层面。

---

## 六、验证记录

| 验证项 | 方法 | 结果 |
|---|---|---|
| 核心 ABI | `mihomo -v` | ✅ abi2，`go1.26.11`，exit 0 |
| abi1 对照 | `./mihomo-abi1 -v` | ✅ 也能运行（新世界兼容），本文不采用 |
| 二进制校验 | SHA256 vs GitHub API digest | ✅ 一致（`a8d8a080…`） |
| ABI 记录 | `cat ~/.config/mihomo/abi` | ✅ `abi2` |
| 服务自启 | `systemctl --user is-active mihomo` | ✅ active |
| 订阅中转服务 | `systemctl --user is-active mihomo-sub-relay` | ✅ active |
| 控制 API | `GET /version` | ✅ `{"meta":true,"version":"v1.19.34"}` |
| 代理端口 | `ss -tln` | ✅ 7890/9090/1053 监听 |
| 面板 | `GET /ui/` | ✅ 200，160 文件 / 8.2 MB |
| GEO 数据 | 三个文件 SHA256 | ✅ 全部与官方 digest 一致 |
| 中转（无 PyYAML） | 本地模拟机场 → 18090 | ✅ base64 → 3 节点 JSON；Clash YAML → 原样透传 |
| mihomo 解析中转输出 | 测试实例拉 `http://127.0.0.1:18090/sub` | ✅ provider 解析出 3 个节点（JSON 作为 YAML 被接受） |
| DNS 解析 | `GET /dns/query?name=api.ip.sb` | ✅ 立即返回（修 fallback 前为超时） |
| 代理端口 | 经 7890 访问 baidu / api.ip.sb | ✅ 200（0.06 s / 0.38 s，DIRECT 路径） |
| 订阅加载 | `GET /providers/proxies` | ✅ 33 节点（订阅地址含 token，不入库） |
| 节点延迟 | `GET /group/PROXY/delay` | ✅ 32/32 有有效延迟（79 ms ~ 1 s） |
| 出口 | 经 7890 访问 `api.ip.sb/ip` | ✅ 新加坡节点（IPv6 出口） |
| 墙外站点 | 经 7890 访问 Google / YouTube / GitHub | ✅ 204 / 200 / 200（0.4~0.9 s） |

---

## 七、已知限制

1. **linger 未开启**：注销桌面后用户服务会停止。常驻需 `sudo loginctl enable-linger $USER`；
2. **无 TUN 全局透明代理**：用户级 systemd 拿不到 `CAP_NET_ADMIN`，需要 root 装系统级服务；
3. **订阅链接含 token**：只存在于本机 `~/.config/mihomo/config.yaml`（已设 600 权限），仓库模板仍是占位符；
4. **面板改配置不持久**：`PATCH /configs` 只改运行时，不写回 `config.yaml`；
5. **7890 对局域网开放且无密码**：`allow-lan: true` + `bind-address: '*'`，建议按 [USAGE.md §五](./USAGE.md) 收紧。

---

## 八、复现步骤

```bash
cd deploy/loongarch64

# 0) 只看环境，不改动
./install.sh --check

# 1) 全自动安装（自动判定 abi2/abi1；直连慢会自动走镜像）
./install.sh

# 2) 填订阅（直连模式）
mihomo-sub 'https://你的订阅链接'

# 2b) 机场只回 base64 时（本机无 PyYAML 也可用）
mihomo-sub --relay 'https://你的订阅链接'

# 3) 打开面板
mihomo-panel
```

需要强制变体时：

```bash
./install.sh --abi abi2
# 或
MIHOMO_ABI=abi2 ./install.sh
```

---

## 九、本机文件清单

```
~/.local/bin/mihomo                            官方 abi2 核心，SHA256 已验证
~/.local/bin/mihomo-panel                      打开图形面板
~/.local/bin/mihomo-sub                        订阅管理（直连/中转双模式）
~/.local/bin/mihomo-status                     状态速查（含 ABI 行）
~/.local/bin/mihomo-sub-relay                  base64 → YAML 中转（PyYAML 可选）

~/.config/mihomo/config.yaml                   主配置
~/.config/mihomo/abi                           ABI 判定结果（abi2）
~/.config/mihomo/mihomo.log                    运行日志
~/.config/mihomo/relay.log                     中转日志
~/.config/mihomo/ui/                           MetaCubeXD 面板（160 文件）
~/.config/mihomo/providers/                    订阅缓存
~/.config/mihomo/{country.mmdb,geoip.metadb,geosite.dat}  地理数据

~/.config/systemd/user/mihomo.service          mihomo 用户服务
~/.config/systemd/user/mihomo-sub-relay.service 中转用户服务
~/.local/share/applications/mihomo-panel.desktop  KDE 菜单入口
```
