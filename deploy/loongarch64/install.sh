#!/usr/bin/env bash
#
# mihomo 在 LoongArch64 上的部署脚本（自动判定 abi1 / abi2）
#
#   ./install.sh              完整部署（自动选 ABI）
#   ./install.sh --check      只做环境自检，不改动任何东西
#   ./install.sh --abi abi2   强制指定 ABI 变体（abi1 | abi2）
#                             已装的变体与之不一致时会重新下载安装
#   ./install.sh --help       显示帮助
#
# 幂等：重复执行安全；已存在的配置文件不会被覆盖（避免清掉你的订阅地址）。
# 环境变量：MIHOMO_VERSION（默认 latest）、MIHOMO_ABI、MIHOMO_GH_PROXY。

set -euo pipefail

BIN_DIR="$HOME/.local/bin"
CFG_DIR="$HOME/.config/mihomo"
UNIT_DIR="$HOME/.config/systemd/user"
APP_DIR="$HOME/.local/share/applications"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REPO="MetaCubeX/mihomo"
UI_REPO="MetaCubeX/metacubexd"
RULES_REPO="MetaCubeX/meta-rules-dat"
VERSION="${MIHOMO_VERSION:-latest}"
ABI_REQ="${MIHOMO_ABI:-auto}"
GH_PROXY="${MIHOMO_GH_PROXY:-https://gh-proxy.com}"   # 直连过慢时的传输镜像；内容仍按官方 SHA256 校验
UI_BRANCH="gh-pages"

RELEASE_TAG=""
declare -A ASSET_DIGEST=()
declare -A GEO_DIGEST=()

c_ok()   { printf '\033[32m%s\033[0m\n' "$*"; }
c_warn() { printf '\033[33m%s\033[0m\n' "$*"; }
c_err()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
c_step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

die() { c_err "✗ $*"; exit 1; }

# ---------- ABI 判定 ----------
glibc_version() { getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2}'; }

# 新世界（LoongArch ABI2）的判据：glibc >= 2.36（上游首个支持 LoongArch 的版本）。
# 旧世界（Loongnix 20 等）为 glibc 2.28 + 4.19 内核。
is_new_world() {
    local g; g="$(glibc_version)"
    [ -n "$g" ] || return 1
    [ "$(printf '%s\n%s\n' 2.36 "$g" | sort -V | head -1)" = "2.36" ]
}

abi_world() {
    case "$1" in
        abi1) echo "旧世界" ;;
        abi2) echo "新世界" ;;
        *)    echo "未知" ;;
    esac
}

abi_order() {
    if [ "$ABI_REQ" != "auto" ]; then
        printf '%s\n' "$ABI_REQ"
        return
    fi
    if is_new_world; then printf 'abi2\nabi1\n'; else printf 'abi1\nabi2\n'; fi
}

# ---------- 下载与校验 ----------
# 先直连 GitHub（限时），失败或过慢则改走镜像。镜像只负责传输，
# 最终仍用 api.github.com 公布的官方 SHA256 校验，杜绝被镜像掉包。
MIRROR_WARNED=0
warn_mirror_once() {
    [ "$MIRROR_WARNED" -eq 0 ] || return 0
    MIRROR_WARNED=1
    c_warn "  GitHub 直连失败或过慢，改用镜像 ${GH_PROXY}（内容按官方 SHA256 校验）"
}

fetch_github() {
    local url="$1" out="$2" part="$2.part"
    rm -f "$part"
    if timeout 30 wget -q --tries=1 --timeout=15 -O "$part" "$url" 2>/dev/null; then
        mv "$part" "$out"
        return 0
    fi
    rm -f "$part"
    if [ -n "$GH_PROXY" ]; then
        warn_mirror_once
        if wget -q --tries=2 --timeout=30 -O "$out" "${GH_PROXY%/}/$url" 2>/dev/null; then
            return 0
        fi
        rm -f "$out"
    fi
    return 1
}

fetch_json() {
    local url="$1"
    curl -fsSL --max-time 25 "$url" 2>/dev/null \
        || { [ -n "$GH_PROXY" ] && curl -fsSL --max-time 25 "${GH_PROXY%/}/$url" 2>/dev/null; }
}

verify_sha256() {  # $1=文件 $2=官方 digest（可空）
    # 返回 0：校验通过或没有 digest 可比（调用方自行提示"未校验"）
    # 返回 1：校验失败，且已删除该文件
    local f="$1" want="$2" got
    [ -n "$want" ] || return 0
    got="$(sha256sum "$f" | awk '{print $1}')"
    if [ "$got" != "${want#sha256:}" ]; then
        c_err "  ✗ SHA256 校验失败：$(basename "$f")（期望 ${want#sha256:}，实际 ${got}），已删除"
        rm -f "$f"
        return 1
    fi
}

load_release_meta() {
    [ -n "$RELEASE_TAG" ] && return 0
    local url json
    # 显式指定版本时，release tag 就是版本号本身，不必等 API 反查；
    # API 只用于取官方 digest，取不到就降级为"不校验"继续下载。
    [ "$VERSION" = "latest" ] || RELEASE_TAG="$VERSION"
    if [ "$VERSION" = "latest" ]; then
        url="https://api.github.com/repos/$REPO/releases/latest"
    else
        url="https://api.github.com/repos/$REPO/releases/tags/$RELEASE_TAG"
    fi
    json="$(fetch_json "$url" || true)"
    if [ -z "$json" ]; then
        if [ -n "$RELEASE_TAG" ]; then
            c_warn "  无法获取 Release 元数据，跳过 SHA256 校验（按 MIHOMO_VERSION=$RELEASE_TAG 下载）"
        else
            c_warn "  无法获取 Release 元数据，跳过 SHA256 校验与自动版本解析"
        fi
        return 0
    fi
    if [ -z "$RELEASE_TAG" ]; then
        RELEASE_TAG="$(python3 -c 'import json,sys;print(json.load(sys.stdin)["tag_name"])' <<<"$json")"
    fi
    while IFS=$'\t' read -r n d; do
        [ -n "$d" ] && ASSET_DIGEST["$n"]="$d"
    done < <(python3 - "$json" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
for a in d.get("assets", []):
    if a.get("name", "").endswith(".gz"):
        print(a["name"], a.get("digest") or "", sep="\t")
PY
)
}

load_geo_meta() {
    local json
    json="$(fetch_json "https://api.github.com/repos/$RULES_REPO/releases/latest" || true)"
    [ -n "$json" ] || return 0
    while IFS=$'\t' read -r n d; do
        [ -n "$d" ] && GEO_DIGEST["$n"]="$d"
    done < <(python3 - "$json" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
for a in d.get("assets", []):
    print(a["name"], a.get("digest") or "", sep="\t")
PY
)
}

# ---------- 环境自检 ----------
systemd_user_ok() { systemctl --user status >/dev/null 2>&1; }

preflight() {
    c_step "环境自检"

    local arch; arch="$(uname -m)"
    if [ "$arch" = "loongarch64" ]; then
        c_ok "  架构：$arch ✅"
    else
        c_warn "  架构：$arch —— 本包针对 loongarch64，其他架构请自行核对"
    fi

    for c in wget curl unzip tar gzip gunzip sha256sum systemctl python3; do
        command -v "$c" >/dev/null || die "缺少命令：$c"
    done
    c_ok "  依赖命令齐全 ✅"

    local kver g; kver="$(uname -r)"; g="$(glibc_version)"
    case "$kver" in
        4.19*|5.4*|5.10*) c_warn "  内核：$kver（早期 loongson 内核，属旧世界）" ;;
        *)                c_ok  "  内核：$kver" ;;
    esac
    if [ -n "$g" ]; then
        if is_new_world; then
            c_ok "  glibc：$g → 新世界（LoongArch ABI2），优先 abi2 变体"
        else
            c_ok "  glibc：$g → 旧世界（LoongArch ABI1 兼容），优先 abi1 变体"
        fi
    else
        c_warn "  无法读取 glibc 版本，按旧世界处理"
    fi

    if systemd_user_ok; then
        c_ok "  systemd 用户实例可用 ✅"
    else
        c_warn "  systemd 用户实例不可用，服务化步骤将被跳过"
    fi

    if python3 -c 'import yaml' >/dev/null 2>&1; then
        c_ok "  PyYAML 可用（订阅中转用标准 YAML 输出）"
    else
        c_warn "  未安装 PyYAML —— 订阅中转会自动降级为 JSON 兼容输出（JSON 是合法 YAML）"
    fi

    if [ -n "${SUDO_USER:-}" ]; then
        c_warn "  当前以 root 运行，HOME 指向 /root，部署位置可能与预期不符"
    fi
}

# ---------- 1. 核心 ----------
install_core() {
    c_step "安装核心（自动判定 ABI）"
    mkdir -p "$BIN_DIR" "$CFG_DIR"

    local recorded="" running=""
    [ -f "$CFG_DIR/abi" ] && recorded="$(tr -d '[:space:]' < "$CFG_DIR/abi")"

    if [ -x "$BIN_DIR/mihomo" ] && "$BIN_DIR/mihomo" -v >/dev/null 2>&1; then
        running="$("$BIN_DIR/mihomo" -v | head -1)"

        # 幂等：没强制指定 ABI，已装且能跑就保持原样，不重复下载
        if [ "$ABI_REQ" = "auto" ]; then
            c_ok "  已存在：$running"
            if [ -z "$recorded" ]; then
                c_warn "  但没有 ABI 记录（旧版安装），mihomo-status 会显示「未记录」；补记：./install.sh --abi abi1|abi2"
            fi
            return 0
        fi

        # 强制指定：与已记录变体一致才跳过，否则重装成指定变体
        if [ "$recorded" = "$ABI_REQ" ]; then
            c_ok "  已存在：$running（ABI=$recorded，与强制指定一致）"
            return 0
        fi
        c_warn "  已存在：$running，但记录的 ABI=${recorded:-未知} ≠ 强制指定的 $ABI_REQ，重新安装"
    elif [ -x "$BIN_DIR/mihomo" ]; then
        c_warn "  已存在的 mihomo 无法运行，重新安装"
    fi

    load_release_meta
    [ -n "$RELEASE_TAG" ] || die "无法确定 Release 版本，请检查网络，或显式设置 MIHOMO_VERSION=v1.19.34"

    local tmp abi name url version_line
    tmp="$(mktemp -d)"
    for abi in $(abi_order); do
        name="mihomo-linux-loong64-$abi-$RELEASE_TAG.gz"
        url="https://github.com/$REPO/releases/download/$RELEASE_TAG/$name"
        c_ok "  尝试 $abi（$(abi_world "$abi")）：$name"

        if ! fetch_github "$url" "$tmp/mihomo.gz"; then
            c_warn "  下载失败，换下一个变体"
            continue
        fi
        if ! verify_sha256 "$tmp/mihomo.gz" "${ASSET_DIGEST[$name]:-}"; then
            c_warn "  校验不通过，换下一个变体"
            continue
        fi
        if ! gunzip -f "$tmp/mihomo.gz" 2>/dev/null; then
            c_warn "  解压失败（文件损坏，常见于镜像返回错误页），换下一个变体"
            rm -f "$tmp/mihomo.gz" "$tmp/mihomo"
            continue
        fi
        chmod +x "$tmp/mihomo"

        # 关键判据：能跑起来才算 ABI 匹配（旧世界上 abi2 会 SIGSEGV）
        if ! "$tmp/mihomo" -v >/dev/null 2>&1; then
            c_warn "  $abi 变体在本机无法运行（ABI 不匹配），换下一个"
            rm -f "$tmp/mihomo"
            continue
        fi

        version_line="$("$tmp/mihomo" -v | head -1)"
        install -m 755 "$tmp/mihomo" "$BIN_DIR/mihomo"
        printf '%s\n' "$abi" > "$CFG_DIR/abi"
        rm -rf "$tmp"
        c_ok "  已安装：$version_line"
        c_ok "  ABI：$abi（$(abi_world "$abi")）→ 记录于 $CFG_DIR/abi"
        return 0
    done

    rm -rf "$tmp"
    die "abi1/abi2 两个变体都没装成功（下载失败、校验不通过或无法运行）；请检查网络 / uname -m / glibc / 内核"
}

# ---------- 2. 配置 ----------
install_config() {
    c_step "部署配置"

    mkdir -p "$CFG_DIR/providers"

    if [ -f "$CFG_DIR/config.yaml" ]; then
        c_warn "  已存在 $CFG_DIR/config.yaml，保持不变（不会覆盖你的订阅地址）"
    else
        cp "$SCRIPT_DIR/config/config.yaml" "$CFG_DIR/config.yaml"
        c_ok "  已写入 $CFG_DIR/config.yaml"
    fi

    # 地理数据（GEOIP / GEOSITE 规则依赖），逐字节校验官方 SHA256
    load_geo_meta
    local f
    for f in country.mmdb geoip.metadb geosite.dat; do
        if [ -s "$CFG_DIR/$f" ]; then
            c_ok "  已存在 $f"
            continue
        fi
        if fetch_github "https://github.com/$RULES_REPO/releases/download/latest/$f" "$CFG_DIR/$f"; then
            if verify_sha256 "$CFG_DIR/$f" "${GEO_DIGEST[$f]:-}"; then
                c_ok "  已下载 $f（$(stat -c %s "$CFG_DIR/$f") 字节）"
            else
                c_warn "  $f 校验失败，已删除（不影响启动，但 GEOIP/GEOSITE 规则会失效）"
            fi
        else
            rm -f "$CFG_DIR/$f"
            c_warn "  $f 下载失败（不影响启动，但 GEOIP/GEOSITE 规则会失效）"
        fi
    done
}

# ---------- 3. 面板 ----------
install_ui() {
    c_step "部署图形面板（MetaCubeXD）"

    if [ -f "$CFG_DIR/ui/index.html" ]; then
        c_ok "  已存在 $CFG_DIR/ui，跳过"
        return 0
    fi

    local tmp; tmp="$(mktemp -d)"
    # 注意：/archive/ 打包接口在部分网络下不通，codeload 更可靠
    if ! fetch_github "https://codeload.github.com/$UI_REPO/zip/refs/heads/$UI_BRANCH" "$tmp/ui.zip"; then
        rm -rf "$tmp"
        die "面板下载失败"
    fi
    unzip -q "$tmp/ui.zip" -d "$tmp/x" \
        || { rm -rf "$tmp"; die "面板包解压失败（下载损坏，可重跑或换 MIHOMO_GH_PROXY）"; }
    # 压缩包顶层目录名随源与镜像而变（metacubexd-gh-pages / MetaCubeX/metacubexd-gh-pages），
    # 因此直接定位含 index.html 的目录，避免写死路径。
    local ui_root
    ui_root="$(find "$tmp/x" -maxdepth 3 -name index.html -printf '%h\n' | head -1)"
    [ -n "$ui_root" ] || { rm -rf "$tmp"; die "面板包结构异常（未找到 index.html）"; }
    mkdir -p "$CFG_DIR/ui"
    cp -a "$ui_root/." "$CFG_DIR/ui/"
    rm -rf "$tmp"
    c_ok "  已部署 $(find "$CFG_DIR/ui" -type f | wc -l) 个文件到 $CFG_DIR/ui ✅"
}

# ---------- 4. 服务 ----------
install_service() {
    c_step "注册 systemd 用户服务"

    if ! systemd_user_ok; then
        c_warn "  systemd 用户实例不可用，跳过"
        return 0
    fi

    mkdir -p "$UNIT_DIR"
    cp "$SCRIPT_DIR/systemd/mihomo.service" "$UNIT_DIR/"
    cp "$SCRIPT_DIR/systemd/mihomo-sub-relay.service" "$UNIT_DIR/"

    systemctl --user daemon-reload
    systemctl --user enable mihomo.service mihomo-sub-relay.service >/dev/null
    systemctl --user restart mihomo.service \
        || c_warn "  mihomo.service 未能启动（详见 systemctl --user status mihomo）"
    systemctl --user restart mihomo-sub-relay.service || c_warn "  中转服务未能启动（仅 base64 订阅模式才需要）"
    c_ok "  mihomo.service：$(systemctl --user is-active mihomo.service)"

    if [ "$(loginctl show-user "$USER" -p Linger --value 2>/dev/null || echo no)" != "yes" ]; then
        c_warn "  未开启 linger：注销桌面后服务会停止。常驻请执行：sudo loginctl enable-linger $USER"
    fi

    # 确认日志确实落盘（%h 展开后要真的写得出）
    sleep 2
    if [ -f "$CFG_DIR/mihomo.log" ]; then
        c_ok "  日志：$CFG_DIR/mihomo.log"
    else
        c_warn "  日志未生成，请检查 systemctl --user status mihomo"
    fi
}

# ---------- 5. 工具脚本 ----------
install_scripts() {
    c_step "安装工具脚本与桌面入口"

    mkdir -p "$BIN_DIR" "$APP_DIR"
    cp "$SCRIPT_DIR/scripts/mihomo-panel" "$SCRIPT_DIR/scripts/mihomo-sub" \
       "$SCRIPT_DIR/scripts/mihomo-status" "$SCRIPT_DIR/scripts/mihomo-sub-relay" "$BIN_DIR/"
    chmod +x "$BIN_DIR/mihomo-panel" "$BIN_DIR/mihomo-sub" \
              "$BIN_DIR/mihomo-status" "$BIN_DIR/mihomo-sub-relay"
    c_ok "  已安装：mihomo-panel / mihomo-sub / mihomo-status / mihomo-sub-relay"

    cp "$SCRIPT_DIR/desktop/mihomo-panel.desktop" "$APP_DIR/"
    # .desktop 不支持 ~ 或 $HOME 展开，用 @HOME@ 占位符在安装时替换
    sed -i "s|@HOME@|$HOME|g" "$APP_DIR/mihomo-panel.desktop"
    chmod 644 "$APP_DIR/mihomo-panel.desktop"
    c_ok "  桌面入口：「Clash 面板 (mihomo)」"

    if ! grep -q "\.local/bin" <<<"$PATH"; then
        c_warn "  ~/.local/bin 不在 PATH 中，请在 ~/.bashrc 加：export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
}

# ---------- 6. 验证 ----------
verify() {
    c_step "验证"
    local ok=0 fail=0
    check() {
        if eval "$2" >/dev/null 2>&1; then
            printf '  ✅ %s\n' "$1"; ok=$((ok+1))
        else
            printf '  ❌ %s\n' "$1"; fail=$((fail+1))
        fi
    }
    sleep 1

    check "核心可执行"          "$BIN_DIR/mihomo -v"
    check "服务运行中"          "systemctl --user is-active mihomo.service"
    check "控制 API 可达"       "wget -q -O - http://127.0.0.1:9090/version"
    if command -v ss >/dev/null 2>&1; then
        check "代理端口 7890 监听" "ss -tln | grep -q 7890"
    else
        c_warn "  未安装 ss（iproute2），跳过端口监听检查"
    fi
    check "面板页面可访问"       "wget -q -O - http://127.0.0.1:9090/ui/"
    check "配置有订阅 provider"  "grep -q 'proxy-providers' \"$CFG_DIR/config.yaml\""

    echo
    if [ "$fail" -eq 0 ]; then
        c_ok "全部通过（$ok 项）"
    else
        c_warn "通过 $ok 项，失败 $fail 项"
    fi
    echo
    local abi_now; abi_now="$(cat "$CFG_DIR/abi" 2>/dev/null || echo '')"
    if [ -n "$abi_now" ]; then
        echo "  当前 ABI：$abi_now（$(abi_world "$abi_now")）"
    else
        echo "  当前 ABI：未记录（旧版安装；补记：./install.sh --abi abi1|abi2）"
    fi
    echo "  下一步：  mihomo-sub 'https://你的订阅链接'   # 填订阅"
    echo "            mihomo-panel                     # 打开面板"
}

print_check() {
    preflight
    echo
    if [ -x "$BIN_DIR/mihomo" ] && "$BIN_DIR/mihomo" -v >/dev/null 2>&1; then
        echo "核心：$("$BIN_DIR/mihomo" -v | head -1)"
        echo "ABI ：$(cat "$CFG_DIR/abi" 2>/dev/null || echo '未记录（旧版安装）')"
    else
        echo "核心：未安装或无法运行"
    fi
    systemctl --user is-active mihomo.service 2>/dev/null | sed 's/^/服务：/' || true
}

case "${1:-}" in
    --help|-h)
        cat <<'EOF'
mihomo 在 LoongArch64 上的部署脚本（自动判定 abi1 / abi2）

  ./install.sh              完整部署（自动选 ABI）
  ./install.sh --check      只做环境自检，不改动任何东西
  ./install.sh --abi abi2   强制指定 ABI 变体（abi1 | abi2）
                            已装的变体与之不一致时会重新下载安装
  ./install.sh --help       显示帮助

幂等：重复执行安全；已存在的配置文件不会被覆盖（避免清掉你的订阅地址）。
环境变量：MIHOMO_VERSION（默认 latest）、MIHOMO_ABI、MIHOMO_GH_PROXY。
EOF
        exit 0 ;;
    --check)
        print_check
        exit 0 ;;
    --abi)
        [ -n "${2:-}" ] || die "用法：./install.sh --abi abi1|abi2"
        case "$2" in abi1|abi2) ABI_REQ="$2" ;; *) die "ABI 只能是 abi1 或 abi2" ;; esac
        preflight
        install_core
        install_config
        install_ui
        install_service
        install_scripts
        verify
        ;;
    "")
        preflight
        install_core
        install_config
        install_ui
        install_service
        install_scripts
        verify
        ;;
    *)
        die "未知参数：$1（可用：--check / --abi abi1|abi2 / --help）" ;;
esac
