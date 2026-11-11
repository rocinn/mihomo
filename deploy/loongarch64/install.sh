#!/usr/bin/env bash
#
# mihomo 在 LoongArch64 上的部署脚本
#
#   ./install.sh              完整部署
#   ./install.sh --check      只做环境自检,不改动任何东西
#   ./install.sh --help       显示帮助
#
# 幂等:重复执行安全;已存在的配置文件不会被覆盖(避免清掉你的订阅地址)。

set -euo pipefail

BIN_DIR="$HOME/.local/bin"
CFG_DIR="$HOME/.config/mihomo"
UNIT_DIR="$HOME/.config/systemd/user"
APP_DIR="$HOME/.local/share/applications"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REPO="MetaCubeX/mihomo"
UI_REPO="MetaCubeX/metacubexd"
RULES_REPO="MetaCubeX/meta-rules-dat"
VERSION="${MIHOMO_VERSION:-latest}"          # latest 或 v1.19.33 这样
UI_BRANCH="gh-pages"

c_ok()   { printf '\033[32m%s\033[0m\n' "$*"; }
c_warn() { printf '\033[33m%s\033[0m\n' "$*"; }
c_err()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
c_step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

die() { c_err "✗ $*"; exit 1; }

# ---------- 环境自检 ----------
preflight() {
    c_step "环境自检"

    local arch; arch="$(uname -m)"
    if [ "$arch" = "loongarch64" ]; then
        c_ok "  架构: $arch ✅"
    else
        c_warn "  架构: $arch —— 本包针对 loongarch64,其他架构请自行核对 ABI"
    fi

    for c in wget unzip tar gzip systemctl; do
        command -v "$c" >/dev/null || die "缺少命令: $c"
    done
    c_ok "  依赖命令齐全 ✅"

    # 内核版本 —— 早期 LoongArch 内核无法运行 abi2
    local kver; kver="$(uname -r)"
    case "$kver" in
        4.19*|5.4*|5.10*) c_warn "  内核: $kver (早期 loongson 内核,abi2 变体会段错误)" ;;
        *)               c_ok  "  内核: $kver" ;;
    esac

    # systemd 用户实例是否可用
    if systemctl --user is-system-running >/dev/null 2>&1; then
        c_ok "  systemd 用户实例可用 ✅"
    else
        c_warn "  systemd 用户实例不可用,服务化步骤将被跳过"
    fi

    if [ -n "${SUDO_USER:-}" ]; then
        c_warn "  当前以 root 运行,HOME 指向 /root,部署位置可能与预期不符"
    fi
}

# ---------- 1. 核心 ----------
install_core() {
    c_step "安装核心(必须是 abi1 变体)"

    mkdir -p "$BIN_DIR"
    if [ -x "$BIN_DIR/mihomo" ]; then
        c_ok "  已存在: $("$BIN_DIR/mihomo" -v 2>/dev/null | head -1)"
        return
    fi

    local tmp; tmp="$(mktemp -d)"
    local url
    if [ "$VERSION" = "latest" ]; then
        url="https://github.com/$REPO/releases/latest/download/mihomo-linux-loong64-abi1-$(fetch_latest_tag).gz"
    else
        url="https://github.com/$REPO/releases/download/$VERSION/mihomo-linux-loong64-abi1-$VERSION.gz"
    fi

    c_ok "  下载: $url"
    wget -q --timeout=30 --tries=3 -O "$tmp/mihomo.gz" "$url" || die "下载失败:$url"
    gunzip -f "$tmp/mihomo.gz"
    chmod +x "$tmp/mihomo"

    # 关键验证:abi1 在本机必须能正常启动,不能段错误
    if ! "$tmp/mihomo" -v >/dev/null 2>&1; then
        rm -rf "$tmp"
        die "该二进制在本机无法运行(段错误)。请确认下载的是 abi1 变体,
     并核对内核是否支持 LoongArch ABI1。"
    fi
    c_ok "  版本: $("$tmp/mihomo" -v | head -1)"

    install -m 755 "$tmp/mihomo" "$BIN_DIR/mihomo"
    rm -rf "$tmp"
    c_ok "  已安装: $BIN_DIR/mihomo ✅"
}

fetch_latest_tag() {
    wget -q -O - "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
        | python3 -c "import json,sys;print(json.load(sys.stdin)['tag_name'])" 2>/dev/null \
        || echo "v1.19.33"
}

# ---------- 2. 配置 ----------
install_config() {
    c_step "部署配置"

    mkdir -p "$CFG_DIR/providers"

    if [ -f "$CFG_DIR/config.yaml" ]; then
        c_warn "  已存在 $CFG_DIR/config.yaml,保持不变(不会覆盖你的订阅地址)"
    else
        cp "$SCRIPT_DIR/config/config.yaml" "$CFG_DIR/config.yaml"
        c_ok "  已写入 $CFG_DIR/config.yaml"
    fi

    # 地理数据
    local f
    for f in country.mmdb geoip.metadb geosite.dat; do
        if [ -s "$CFG_DIR/$f" ]; then
            c_ok "  已存在 $f"
        else
            wget -q --timeout=30 -O "$CFG_DIR/$f" \
                "https://github.com/$RULES_REPO/releases/download/latest/$f" \
                && c_ok "  已下载 $f" || c_warn "  $f 下载失败(不影响启动,但 GEOIP 规则会失效)"
        fi
    done
}

# ---------- 3. 面板 ----------
install_ui() {
    c_step "部署图形面板 (MetaCubeXD)"

    if [ -f "$CFG_DIR/ui/index.html" ]; then
        c_ok "  已存在 $CFG_DIR/ui,跳过"
        return
    fi

    local tmp; tmp="$(mktemp -d)"
    # 注意:/archive/ 打包接口在部分网络下不通,codeload 更可靠
    wget -q --timeout=30 --tries=2 -O "$tmp/ui.zip" \
        "https://codeload.github.com/$UI_REPO/zip/refs/heads/$UI_BRANCH" \
        || { rm -rf "$tmp"; die "面板下载失败"; }
    unzip -q "$tmp/ui.zip" -d "$tmp/x"
    mkdir -p "$CFG_DIR/ui"
    cp -a "$tmp/x/$UI_REPO-$UI_BRANCH/." "$CFG_DIR/ui/"
    rm -rf "$tmp"
    c_ok "  已部署 $(find "$CFG_DIR/ui" -type f | wc -l) 个文件到 $CFG_DIR/ui ✅"
}

# ---------- 4. 服务 ----------
install_service() {
    c_step "注册 systemd 用户服务"

    if ! systemctl --user is-system-running >/dev/null 2>&1; then
        c_warn "  systemd 用户实例不可用,跳过"
        return
    fi

    mkdir -p "$UNIT_DIR"
    cp "$SCRIPT_DIR/systemd/mihomo.service" "$UNIT_DIR/"
    cp "$SCRIPT_DIR/systemd/mihomo-sub-relay.service" "$UNIT_DIR/"

    systemctl --user daemon-reload
    systemctl --user enable --now mihomo.service
    systemctl --user enable --now mihomo-sub-relay.service
    c_ok "  mihomo.service: $(systemctl --user is-active mihomo.service)"

    # 确认日志确实落盘(%h 展开后要真的写得出)
    sleep 2
    if [ -f "$CFG_DIR/mihomo.log" ]; then
        c_ok "  日志: $CFG_DIR/mihomo.log"
    else
        c_warn "  日志未生成,请检查 systemctl --user status mihomo"
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
    c_ok "  已安装: mihomo-panel / mihomo-sub / mihomo-status / mihomo-sub-relay"

    cp "$SCRIPT_DIR/desktop/mihomo-panel.desktop" "$APP_DIR/"
    # .desktop 不支持 ~ 或 $HOME 展开,用 @HOME@ 占位符在安装时替换
    sed -i "s|@HOME@|$HOME|g" "$APP_DIR/mihomo-panel.desktop"
    chmod 644 "$APP_DIR/mihomo-panel.desktop"
    c_ok "  桌面入口: 「Clash 面板 (mihomo)」"

    if ! grep -q "\.local/bin" <<<"$PATH"; then
        c_warn "  ~/.local/bin 不在 PATH 中,请在 ~/.bashrc 加: export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
}

# ---------- 6. 验证 ----------
verify() {
    c_step "验证"
    local ok=0 fail=0
    check() { if eval "$2" >/dev/null 2>&1; then printf '  ✅ %s\n' "$1"; ok=$((ok+1)); else printf '  ❌ %s\n' "$1"; fail=$((fail+1)); fi; }

    check "核心可执行"            "$BIN_DIR/mihomo -v"
    check "服务运行中"            "systemctl --user is-active mihomo.service"
    check "控制 API 可达"         "wget -q -O - http://127.0.0.1:9090/version"
    check "代理端口 7890 监听"     "ss -tln | grep -q 7890"
    check "面板页面可访问"         "wget -q -O - http://127.0.0.1:9090/ui/"
    check "配置有订阅 provider"    "grep -q 'proxy-providers' $CFG_DIR/config.yaml"

    echo
    if [ "$fail" -eq 0 ]; then
        c_ok "全部通过 ($ok 项)"
    else
        c_warn "通过 $ok 项,失败 $fail 项"
    fi
    echo
    echo "  下一步:  mihomo-sub 'https://你的订阅链接'   # 填订阅"
    echo "            mihomo-panel                     # 打开面板"
}

case "${1:-}" in
    --help|-h)
        sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
        exit 0 ;;
    --check)
        preflight
        echo
        [ -x "$BIN_DIR/mihomo" ] && echo "核心: $("$BIN_DIR/mihomo" -v | head -1)" || echo "核心: 未安装"
        systemctl --user is-active mihomo.service 2>/dev/null || true
        exit 0 ;;
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
        die "未知参数:$1(可用:--check / --help)" ;;
esac
