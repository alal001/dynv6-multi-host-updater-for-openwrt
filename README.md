# dynv6-multi-host-updater
### 一个用于 OpenWrt 的 dynv6 DDNS 更新脚本，支持自动更新主域名和多个子域名，通过 MAC 地址自动获取设备的 IPv6 地址。

## 功能特点
✅ 自动更新主域名（zone）的 IPv4 和 IPv6 前缀

✅ 支持同时更新多个子域名（如 router、nas、camera 等）

✅ 通过 MAC 地址自动获取设备的全球单播 IPv6 地址

✅ 支持回退机制：无法获取设备 IP 时自动使用路由器地址

✅ 智能判断 IP 是否变化，避免无效更新

✅ 支持 IPv4/IPv6 双栈（可单独关闭 IPv4）

✅ 可自定义网络接口（适用于不同网络环境）

✅ 纯 Shell 脚本，无额外依赖（只需 curl）

使用方法
1. 准备工作
在 dynv6 注册账号，获取你的域名（如 yourname.dynv6.net）

获取你的 dynv6 Token（在 My Zones → 你的域名 → Instructions → Benutzername）

确保 OpenWrt 已安装 curl

2. 一键安装
```bash
wget -O /tmp/install.sh https://raw.githubusercontent.com/yourname/dynv6-multi-host-updater/main/install.sh
chmod +x /tmp/install.sh
sh /tmp/install.sh
```
安装过程会依次询问：

你的 dynv6 域名

dynv6 Token

是否启用 IPv4 更新（如无公网 IPv4 可选否）

IPv4 网络接口（默认 pppoe-wan）

IPv6 网络接口（默认 br-lan）

需要更新的子域名及对应的 MAC 地址

3. 手动配置（可选）
如果不想用一键安装，也可以手动配置：

## 下载脚本
```bash
wget -O /etc/dynv6-update.sh https://raw.githubusercontent.com/yourname/dynv6-multi-host-updater/main/dynv6-update.sh
chmod +x /etc/dynv6-update.sh
```
## 编辑配置
```bash
vi /etc/dynv6-update.sh
```
修改以下配置项：

```bash
domain='yourname.dynv6.net'          # 你的域名
username='your_token_here'           # dynv6 Token
```

## 网络接口配置（根据实际情况修改）
```bash
IPV4_IFACE="pppoe-wan"    # IPv4接口(如pppoe-wan、eth0.2等）
IPV6_IFACE="br-lan"       # IPv6接口（如br-lan、eth0等)
```
## 是否启用 IPv4 更新（如无公网 IPv4 则设为 false）
```bash
ENABLE_IPV4=true
```
## 子域名列表（按顺序，router 是路由器自身）
```bash
subDomains='"router" "hall" "nas" "camera"'
```
## 子域名对应的 MAC 地址（router 占位符任意，其他填实际 MAC）
```bash
subMacs="00:00:00:00:00:00 11:22:33:44:55:66 77:88:99:aa:bb:cc dd:ee:ff:00:11:22"
```
4. 手动测试
```bash
/etc/dynv6-update.sh
```
5. 设置定时任务
添加到 crontab，例如每 5 分钟更新一次：

```bash
*/5 * * * * /etc/dynv6-update.sh >> /var/log/dynv6.log 2>&1
```
工作原理
主域名更新：获取路由器的 IPv4/IPv6 地址，更新 zone 的 IP 前缀。

子域名更新：

对于 router 子域名，直接使用路由器 IPv6

对于其他子域名，通过 MAC 地址在邻居表中查找 IPv6

如果查找失败，自动回退到路由器 IPv6

智能判断：每次更新前对比当前 IP 与记录 IP，无变化则跳过

添加新设备
在 subDomains 中添加新子域名（如 "nas"）

在 subMacs 中添加对应的 MAC 地址

在 dynv6 后台手动创建该子域名的 AAAA 记录（只需一次）

运行脚本，自动更新

注意事项
脚本依赖 ip 命令和 curl（OpenWrt 默认已安装）

确保设备的 IPv6 是全球单播地址（以 2 或 3 开头）

子域名首次使用前需要在 dynv6 后台手动创建一次记录

IPv4 接口通常为 pppoe-wan（PPPoE 拨号）或 eth0.2（光猫桥接），请根据实际情况修改

IPv6 接口通常为 br-lan（LAN 桥接），如使用其他接口请修改

日志示例
```text
开始更新 dynv6 域名：yourname.dynv6.net
路由器 IPv4: 123.45.67.89
路由器 IPv6: 2001:db8:1234:5678::1
记录中 IPv4: 123.45.67.89
记录中 IPv6: 2001:db8:1234:5678::1
IP 地址未变化，跳过主域名更新
正在处理子域名: router
已更新子域名: router (AAAA) -> 2001:db8:1234:5678::1
正在处理子域名: hall
已更新子域名: hall (AAAA) -> 2001:db8:1234:5678:51ab:ce5:aeb0:9632
所有更新完成
```

## 删除脚本
```bash
rm -f /etc/dynv6-update.sh
```
## 删除定时任务
```bash
crontab -l | grep -v "dynv6-update.sh" | crontab -
```
## 删除日志
```bash
rm -f /var/log/dynv6.log
```
## 许可证
MIT License

