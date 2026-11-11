# mihomo (Clash.Meta) 本机使用手册

> 适用机器：Loongnix GNU/Linux 20 (DaoXiangHu) / loongarch64 / KDE Plasma (X11)

## 一、为什么是 mihomo 而不是原版 Clash

原版 Clash / Clash Premium 只发布 x86_64 与 arm64 二进制包，**没有 loongarch64 版本**。
Clash.Meta 的继任者 **mihomo** 官方提供 `linux-loong64` 构建，所以本机只能选它。

⚠️ 本机必须使用 **abi1** 变体（3A6000 + 4.19 内核下 abi2 会段错误）：

```bash
# 官方 deb 包安装（需要 root 密码）
wget https://github.com/MetaCubeX/mihomo/releases/latest/download/mihomo-linux-loong64-abi1-v1.19.33.deb
sudo apt install ./mihomo-linux-loong64-abi1-v1.19.33.deb
```

本机当前用的是免 root 的用户级安装：`~/.local/bin/mihomo`（v1.19.33 loong64 abi1）。

### ⚠️ 别被 GitHub 首页骗了

打开 <https://github.com/MetaCubeX/mihomo> 看到的**不是**代理内核，
而是一个无关的 Python 库（崩坏星穹铁道数据模型）—— 因为该仓库的**默认分支 `main`
被无关项目占据**，Clash 核心的真实 Go 源码在 **`Meta` 分支**，而**内核二进制发布在
Releases**（本机就是这么装的，SHA256 与官方 digest 已逐字节校验一致）。

另注意两个仓库别混：

| 仓库 | 是什么 | 本机对应物 |
|---|---|---|
| `MetaCubeX/mihomo` | 代理内核 | `~/.local/bin/mihomo` |
| `MetaCubeX/metacubexd` | 网页面板 MetaCubeXD | `~/.config/mihomo/ui/` |

详见 [ADAPTATION.md](./ADAPTATION.md) 第 2.6 节。

## 二、当前安装布局

| 项目 | 位置 |
|---|---|
| 程序 | `~/.local/bin/mihomo` |
| 配置 | `~/.config/mihomo/config.yaml` |
| 面板 UI | `~/.config/mihomo/ui/`（MetaCubeXD） |
| 日志 | `~/.config/mihomo/mihomo.log` |
| 服务单元 | `~/.config/systemd/user/mihomo.service`（已 enable，登录自启） |
| 订阅中转 | `~/.config/systemd/user/mihomo-sub-relay.service` + `~/.local/bin/mihomo-sub-relay` |
| 快捷命令 | `mihomo-panel` / `mihomo-sub` / `mihomo-status` |

端口：`7890` 混合代理(HTTP+SOCKS)、`9090` 控制 API、`1053` DNS。

## 三、打开图形面板（配置节点/开关代理）

```bash
mihomo-panel
```

或浏览器直接访问 <http://127.0.0.1:9090/ui/>，
或从 KDE 应用程序菜单点 **「Clash 面板 (mihomo)」**。

面板能做的：切节点/策略组、看实时流量与连接、看日志、改端口与模式、改 DNS。
面板**不能**做的：添加订阅链接、编辑规则集（那要改 `config.yaml`）。

> 原生 GUI 客户端（Clash Verge Rev、FlClash）均无 loongarch64 构建，只能用网页面板。

## 四、添加节点 / 订阅

### 方式 A：订阅链接（推荐）

```bash
mihomo-sub 'https://你的订阅地址'
```

脚本会改写 `config.yaml` 的 `proxy-providers.mysub.url` 并重启服务。
之后订阅每小时自动更新，节点健康检查每 5 分钟一次。

`proxy-providers.mysub` 里已配好 Clash 伪装头 —— 这是能否正确解析的关键：

```yaml
header:
  User-Agent:
    - "clash.meta"
    - "ClashforWindows/0.20.39"
    - "Clash/1.10.0"
```

机场普遍按 User-Agent 决定返回格式：不带 Clash UA 只返回 base64 编码的
`ss://`/`vmess://` 链接列表，mihomo 的 http provider **解析不了**；
带上 Clash UA 才返回 Clash YAML。加了这行头就不用管机场怎么实现。

查看 / 手动拉取 / 自检：

```bash
mihomo-sub --show     # 当前模式与订阅地址
mihomo-sub --update   # 立即重拉
mihomo-sub --test     # 连通性自检 + 节点统计
```

### 方式 A2：base64 订阅（机场无视 UA 时的兜底）

有些机场无论什么 UA 都只给 base64。已内置本地中转自动转成 Clash YAML：

```bash
mihomo-sub --relay 'https://你的订阅地址'
```

原理：`~/.config/mihomo/relay-upstream` 存上游地址 → `mihomo-sub-relay.service`
（监听 `127.0.0.1:18090`）拉取并转换 → mihomo 从本地地址取 YAML。
支持转换 `ss` / `vmess` / `trojan` / `hysteria2` / `vless` 五种协议。
上游地址只存本地文件（权限 600），不会写进 systemd 单元。

两种模式随时可切，`--show` 会显示当前处于哪种模式。

### 方式 B：手写节点

编辑 `~/.config/mihomo/config.yaml`，把 `proxies:` 段取消注释并填写，例如：

```yaml
proxies:
  - name: "节点A"
    type: ss
    server: 1.2.3.4
    port: 8388
    cipher: aes-256-gcm
    password: "密码"
```

改完 `systemctl --user restart mihomo`。

## 五、安全提醒：7890 是开放代理

`config.yaml` 里 `allow-lan: true` + `bind-address: '*'`，意味着 **7890 端口对整个
局域网开放且无密码**。本机所在网络是共享网段，同网段其他设备
或用户可以借用你的代理、甚至用它访问你的流量。

两种收紧方式，任选其一改 `config.yaml` 后 `systemctl --user restart mihomo`：

```yaml
# 方案 A：加认证（仍允许局域网其他设备使用，但需要密码）
authentication:
  - "用户名:密码"
allow-lan: true

# 方案 B：只允许本机使用（最安全）
allow-lan: false
bind-address: 127.0.0.1
```

控制面板 9090 目前已限定 `127.0.0.1`，不受影响。

## 六、让流量走代理

### 手动代理（当前模式，无需 root）

给单个程序加代理：

```bash
export https_proxy=http://127.0.0.1:7890
export http_proxy=http://127.0.0.1:7890
export all_proxy=socks5://127.0.0.1:7890
```

KDE 系统代理：系统设置 → 网络 → 网络代理 → 手动，
HTTP/HTTPS 填 `127.0.0.1:7890`，SOCKS 填 `127.0.0.1:7890`。
（`~/.config/kioslaverc` 里当前指向的是**宿主机**上的代理，不是本机的 mihomo。）

### TUN 全局透明代理（需要 root）

用户级 systemd 服务拿不到 `CAP_NET_ADMIN`，TUN 模式必须用系统级服务：

```bash
sudo apt install ./mihomo-linux-loong64-abi1-v1.19.33.deb   # 自带 systemd 服务
sudo systemctl enable --now mihomo
```

再在 `config.yaml` 开启：

```yaml
tun:
  enable: true
  stack: gvisor
  auto-route: true
  auto-detect-interface: true
  dns-hijack:
    - any:53
```

## 七、常用命令

```bash
mihomo-status                       # 状态速查（服务/端口/代理组/订阅/日志）
systemctl --user status mihomo      # 服务详情
systemctl --user restart mihomo     # 重启（改完配置后）
systemctl --user stop mihomo        # 停止
systemctl --user enable mihomo      # 开机/登录自启（已开启）
tail -f ~/.config/mihomo/mihomo.log # 实时日志
```

## 八、常见问题

**面板打不开** → `systemctl --user status mihomo` 看是否运行；端口 9090 是否被占。

**订阅 404** → 订阅地址填错或已过期，用 `mihomo-sub` 重新设置。

**代理通但节点不变** → 面板里选策略组，再点「自动选择」跑一遍测速。

**开机不自动启动** → `systemctl --user enable mihomo`；本机 linger 已开（`Linger=yes`），
用户服务无需登录桌面也会跑。
