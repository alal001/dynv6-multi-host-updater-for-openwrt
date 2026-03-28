#!/bin/sh

# ============================================
# dynv6 多主机更新脚本 - 一键安装
# 支持 IPv4/IPv6 双栈，自定义接口
# ============================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}dynv6 多主机更新脚本 - 一键安装${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 检查环境
if ! command -v opkg >/dev/null 2>&1; then
    echo -e "${RED}错误：请在 OpenWrt 上运行此脚本${NC}"
    exit 1
fi

# 检查依赖
echo -e "${YELLOW}[1/7] 检查依赖...${NC}"
if ! command -v curl >/dev/null 2>&1; then
    echo "正在安装 curl..."
    opkg update && opkg install curl
fi
echo -e "${GREEN}✓ 依赖检查完成${NC}"
echo ""

# 输入域名
echo -e "${YELLOW}[2/7] 配置域名${NC}"
read -p "请输入你的 dynv6 域名（如 yourname.dynv6.net）: " DOMAIN
[ -z "$DOMAIN" ] && { echo -e "${RED}域名不能为空${NC}"; exit 1; }
echo ""

# 输入 Token
echo -e "${YELLOW}[3/7] 配置 Token${NC}"
echo "请在 dynv6 控制台 → My Zones → 你的域名 → Instructions → Benutzername 中查看"
read -p "请输入你的 dynv6 Token: " TOKEN
[ -z "$TOKEN" ] && { echo -e "${RED}Token 不能为空${NC}"; exit 1; }
echo ""

# 配置 IPv4
echo -e "${YELLOW}[4/7] 配置 IPv4${NC}"
read -p "是否启用 IPv4 更新？(y/n, 默认 y): " ENABLE_IPV4
ENABLE_IPV4=${ENABLE_IPV4:-y}
if [ "$ENABLE_IPV4" = "y" ] || [ "$ENABLE_IPV4" = "Y" ]; then
    ENABLE_IPV4=true
    read -p "请输入 IPv4 网络接口（默认 pppoe-wan）: " IPV4_IFACE
    IPV4_IFACE=${IPV4_IFACE:-pppoe-wan}
else
    ENABLE_IPV4=false
    IPV4_IFACE=""
fi
echo ""

# 配置 IPv6
echo -e "${YELLOW}[5/7] 配置 IPv6${NC}"
read -p "请输入 IPv6 网络接口（默认 br-lan）: " IPV6_IFACE
IPV6_IFACE=${IPV6_IFACE:-br-lan}
echo ""

# 输入子域名和 MAC 地址
echo -e "${YELLOW}[6/7] 配置子域名${NC}"
echo "请输入需要更新的子域名（每行一个，输入空行结束）"
echo "示例：router（路由器自身）、hall、nas、camera 等"
echo "注意：router 会自动使用路由器地址，无需 MAC"
echo ""

SUBDOMAINS=""
SUBMACS=""
count=0
while true; do
    read -p "子域名 (留空结束): " sub
    [ -z "$sub" ] && break
    count=$((count + 1))
    SUBDOMAINS="$SUBDOMAINS \"$sub\""
    
    if [ "$sub" = "router" ]; then
        SUBMACS="$SUBMACS \"00:00:00:00:00:00\""
        echo "  → router 将使用路由器地址，无需 MAC"
    else
        read -p "  主机 $sub 的 MAC 地址: " mac
        SUBMACS="$SUBMACS \"$mac\""
        echo "  → 已添加 $sub ($mac)"
    fi
    echo ""
done

if [ $count -eq 0 ]; then
    echo -e "${RED}至少需要添加一个子域名${NC}"
    exit 1
fi
echo -e "${GREEN}✓ 已添加 $count 个子域名${NC}"
echo ""

# 下载脚本模板
echo -e "${YELLOW}[7/7] 生成并安装脚本...${NC}"
SCRIPT_PATH="/etc/dynv6-update.sh"

# 生成最终脚本
cat > "$SCRIPT_PATH" <<EOF
#!/bin/sh

# ============================================
# dynv6 多主机子域名更新脚本
# 自动生成于 $(date)
# ============================================

url="https://dynv6.com/api/v2/zones"
domain="$DOMAIN"
username="$TOKEN"

# 网络接口配置
IPV4_IFACE="$IPV4_IFACE"
IPV6_IFACE="$IPV6_IFACE"
ENABLE_IPV4=$ENABLE_IPV4

# 子域名列表
subDomains='$SUBDOMAINS'
# 子域名对应的 MAC 地址
subMacs='$SUBMACS'

# 获取路由器 IPv4 地址
get_router_ipv4() {
    ip addr show "\$IPV4_IFACE" | grep 'inet ' | awk '{print \$2}' | cut -d'/' -f1 | head -1
}

# 获取路由器 IPv6 地址
get_router_ipv6() {
    ip -6 addr show "\$IPV6_IFACE" | grep 'global' | awk -F' ' '{print \$2}' | cut -d'/' -f1 | head -1
}

# 通过 MAC 地址获取主机 IPv6
get_host_ipv6() {
    local mac="\$1"
    ip -6 neigh show | grep -i "\$mac" | grep -v FAILED | grep -E '^[23]' | awk '{print \$1}' | head -1
}

# 获取 zone ID
get_zone_id() {
    curl -s -H "Authorization: Bearer \${username}" -H "Accept: application/json" "\${url}/by-name/\${domain}" | sed 's/.*"id":\([0-9]*\).*/\1/'
}

# 获取 zone 的当前 IP
get_zone_ips() {
    curl -s -H "Authorization: Bearer \${username}" -H "Accept: application/json" "\${url}/\${zone_id}"
}

# 更新主域名
update_zone() {
    local myIP4=\$(get_router_ipv4)
    local myIP6=\$(get_router_ipv6)
    local payload="{\"ipv4address\": \"\${myIP4}\", \"ipv6prefix\": \"\${myIP6}\"}"
    curl -s -X PATCH -H "Authorization: Bearer \${username}" -H "Content-Type: application/json" -d "\${payload}" "\${url}/\${zone_id}"
}

# 获取所有记录
get_records() {
    curl -s -H "Authorization: Bearer \${username}" -H "Accept: application/json" "\${url}/\${zone_id}/records"
}

# 更新单条记录
update_record() {
    local sub="\$1"
    local type="\$2"
    local data="\$3"
    local record_id="\$4"
    
    local name_field="\"\${sub}\""
    local payload="{\"name\": \${name_field}, \"type\": \"\${type}\", \"data\": \"\${data}\"}"
    curl -s -X PATCH -H "Authorization: Bearer \${username}" -H "Content-Type: application/json" -d "\${payload}" "\${url}/\${zone_id}/records/\${record_id}"
}

# ==================================== 主逻辑 ====================================
echo "开始更新 dynv6 域名：\${domain}"

zone_id=\$(get_zone_id)
if [ -z "\$zone_id" ]; then
    echo "错误：获取 zone ID 失败"
    exit 1
fi

router_ipv4=\$(get_router_ipv4)
router_ipv6=\$(get_router_ipv6)
echo "路由器 IPv4: \${router_ipv4:-无}"
echo "路由器 IPv6: \${router_ipv6}"

zone_data=\$(get_zone_ips)
last_ipv4=\$(echo "\$zone_data" | sed 's/.*"ipv4address":"\([0-9\.]*\)".*/\1/')
last_ipv6=\$(echo "\$zone_data" | sed 's/.*"ipv6prefix":"\([0-9a-f:]*\)".*/\1/')
echo "记录中 IPv4: \${last_ipv4:-无}"
echo "记录中 IPv6: \${last_ipv6}"

need_update=false
if [ "\$ENABLE_IPV4" = "true" ] && [ -n "\$router_ipv4" ] && [ "\$router_ipv4" != "\$last_ipv4" ]; then
    need_update=true
fi
if [ -n "\$router_ipv6" ] && [ "\$router_ipv6" != "\$last_ipv6" ]; then
    need_update=true
fi

if [ "\$need_update" = "true" ]; then
    echo "IP 地址已变化，更新主域名..."
    update_zone
    echo "主域名 IP 前缀已更新"
else
    echo "IP 地址未变化，跳过主域名更新"
fi

records=\$(get_records)

eval "set -- \$subDomains"
sub_list="\$@"
eval "set -- \$subMacs"
mac_list="\$@"

set -- \$sub_list
for sub in "\$@"; do
    mac=\$(echo \$mac_list | cut -d' ' -f1)
    mac_list=\$(echo \$mac_list | cut -d' ' -f2-)
    
    echo "正在处理子域名: \$sub"
    
    if [ "\$sub" = "router" ]; then
        current_ipv6="\$router_ipv6"
    else
        current_ipv6=\$(get_host_ipv6 "\$mac")
        if [ -z "\$current_ipv6" ]; then
            echo "警告：无法获取子域名 \${sub} 的 IPv6 地址，将使用路由器地址"
            current_ipv6="\$router_ipv6"
        fi
    fi
    
    record_id=\$(echo "\$records" | grep -E '"type":"AAAA".*"name":"'"\$sub"'"' | sed 's/.*"id":\([0-9]*\).*/\1/')
    
    if [ -n "\$record_id" ]; then
        update_record "\$sub" "AAAA" "\$current_ipv6" "\$record_id"
        echo "已更新子域名: \${sub} (AAAA) -> \${current_ipv6}"
    else
        echo "警告：未找到子域名 \${sub} 的 AAAA 记录，请先在 dynv6 后台创建"
    fi
done

echo "所有更新完成"
EOF

chmod +x "$SCRIPT_PATH"
echo -e "${GREEN}✓ 脚本已生成到 $SCRIPT_PATH${NC}"
echo ""

# 测试运行
echo -e "${YELLOW}测试运行脚本...${NC}"
if "$SCRIPT_PATH"; then
    echo -e "${GREEN}✓ 测试成功${NC}"
else
    echo -e "${RED}✗ 测试失败，请检查配置${NC}"
    exit 1
fi
echo ""

# 设置定时任务
echo -e "${YELLOW}设置定时任务（每 5 分钟更新一次）...${NC}"
if crontab -l 2>/dev/null | grep -q "dynv6-update.sh"; then
    echo "定时任务已存在，跳过"
else
    (crontab -l 2>/dev/null; echo "*/5 * * * * $SCRIPT_PATH >> /var/log/dynv6.log 2>&1") | crontab -
    echo -e "${GREEN}✓ 定时任务已添加${NC}"
fi
echo ""

# 完成
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}安装完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "脚本位置: $SCRIPT_PATH"
echo "日志文件: /var/log/dynv6.log"
echo ""
echo "你可以运行以下命令手动测试："
echo "  $SCRIPT_PATH"
echo ""
echo "查看定时任务："
echo "  crontab -l"
echo ""
echo -e "${YELLOW}注意：如果某些子域名提示'未找到记录'，请先在 dynv6 后台手动创建对应的 AAAA 记录${NC}"