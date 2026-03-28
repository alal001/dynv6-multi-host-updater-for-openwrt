#!/bin/sh

# ============================================
# dynv6 多主机子域名更新脚本 (OpenWrt 版)
# 支持 IPv4/IPv6 双栈，支持自定义接口
# ============================================

url="https://dynv6.com/api/v2/zones"
domain='yourname.dynv6.net'
username='your_token'

# 网络接口配置（根据实际情况修改）
IPV4_IFACE="pppoe-wan"      # IPv4 接口（如 pppoe-wan、eth0.2 等）
IPV6_IFACE="br-lan"         # IPv6 接口（如 br-lan、eth0 等）

# 是否启用 IPv4 更新（如无公网 IPv4 则设为 false）
ENABLE_IPV4=true

# 子域名列表（按顺序，第一个是 router，对应路由器自身）
subDomains='"router" "hall" "nas" "camera"'
# 子域名对应的 MAC 地址（router 占位符任意，其他填实际 MAC）
subMacs="00:00:00:00:00:00 00:00:00:00:00:00 00:00:00:00:00:00 00:00:00:00:00:00"

# 获取路由器 IPv4 地址
get_router_ipv4() {
    ip addr show "$IPV4_IFACE" | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1 | head -1
}

# 获取路由器 IPv6 地址
get_router_ipv6() {
    ip -6 addr show "$IPV6_IFACE" | grep 'global' | awk -F' ' '{print $2}' | cut -d'/' -f1 | head -1
}

# 通过 MAC 地址获取主机 IPv6（全球单播）
get_host_ipv6() {
    local mac="$1"
    ip -6 neigh show | grep -i "$mac" | grep -v FAILED | grep -E '^[23]' | awk '{print $1}' | head -1
}

# 获取 zone ID
get_zone_id() {
    curl -s -H "Authorization: Bearer ${username}" -H "Accept: application/json" "${url}/by-name/${domain}" | sed 's/.*"id":\([0-9]*\).*/\1/'
}

# 获取 zone 的当前 IPv4 和 IPv6 前缀
get_zone_ips() {
    curl -s -H "Authorization: Bearer ${username}" -H "Accept: application/json" "${url}/${zone_id}"
}

# 更新主域名的 IPv4 和 IPv6 前缀
update_zone() {
    local myIP4=$(get_router_ipv4)
    local myIP6=$(get_router_ipv6)
    local payload="{\"ipv4address\": \"${myIP4}\", \"ipv6prefix\": \"${myIP6}\"}"
    curl -s -X PATCH -H "Authorization: Bearer ${username}" -H "Content-Type: application/json" -d "${payload}" "${url}/${zone_id}"
}

# 获取所有记录
get_records() {
    curl -s -H "Authorization: Bearer ${username}" -H "Accept: application/json" "${url}/${zone_id}/records"
}

# 更新单条记录
update_record() {
    local sub="$1"
    local type="$2"
    local data="$3"
    local record_id="$4"
    
    local name_field="\"${sub}\""
    local payload="{\"name\": ${name_field}, \"type\": \"${type}\", \"data\": \"${data}\"}"
    curl -s -X PATCH -H "Authorization: Bearer ${username}" -H "Content-Type: application/json" -d "${payload}" "${url}/${zone_id}/records/${record_id}"
}

# ==================================== 主逻辑 ====================================
echo "开始更新 dynv6 域名：${domain}"

zone_id=$(get_zone_id)
if [ -z "$zone_id" ]; then
    echo "错误：获取 zone ID 失败"
    exit 1
fi

router_ipv4=$(get_router_ipv4)
router_ipv6=$(get_router_ipv6)

echo "路由器 IPv4: ${router_ipv4:-无}"
echo "路由器 IPv6: ${router_ipv6}"

# 获取 zone 当前 IP
zone_data=$(get_zone_ips)
last_ipv4=$(echo "$zone_data" | sed 's/.*"ipv4address":"\([0-9\.]*\)".*/\1/')
last_ipv6=$(echo "$zone_data" | sed 's/.*"ipv6prefix":"\([0-9a-f:]*\)".*/\1/')
echo "记录中 IPv4: ${last_ipv4:-无}"
echo "记录中 IPv6: ${last_ipv6}"

# 判断是否需要更新主域名
need_update=false
if [ "$ENABLE_IPV4" = "true" ] && [ -n "$router_ipv4" ] && [ "$router_ipv4" != "$last_ipv4" ]; then
    need_update=true
fi
if [ -n "$router_ipv6" ] && [ "$router_ipv6" != "$last_ipv6" ]; then
    need_update=true
fi

if [ "$need_update" = "true" ]; then
    echo "IP 地址已变化，更新主域名..."
    update_zone
    echo "主域名 IP 前缀已更新"
else
    echo "IP 地址未变化，跳过主域名更新"
fi

# 获取所有记录
records=$(get_records)

# 处理子域名
eval "set -- $subDomains"
sub_list="$@"
eval "set -- $subMacs"
mac_list="$@"

set -- $sub_list
for sub in "$@"; do
    mac=$(echo $mac_list | cut -d' ' -f1)
    mac_list=$(echo $mac_list | cut -d' ' -f2-)
    
    echo "正在处理子域名: $sub"
    
    # 获取该子域名的 IPv6
    if [ "$sub" = "router" ]; then
        current_ipv6="$router_ipv6"
    else
        current_ipv6=$(get_host_ipv6 "$mac")
        if [ -z "$current_ipv6" ]; then
            echo "警告：无法获取子域名 ${sub} 的 IPv6 地址，将使用路由器地址"
            current_ipv6="$router_ipv6"
        fi
    fi
    
    record_id=$(echo "$records" | grep -E '"type":"AAAA".*"name":"'"$sub"'"' | sed 's/.*"id":\([0-9]*\).*/\1/')
    
    if [ -n "$record_id" ]; then
        update_record "$sub" "AAAA" "$current_ipv6" "$record_id"
        echo "已更新子域名: ${sub} (AAAA) -> ${current_ipv6}"
    else
        echo "警告：未找到子域名 ${sub} 的 AAAA 记录，请先在 dynv6 后台创建"
    fi
done

echo "所有更新完成"