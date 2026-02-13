#!/bin/bash

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

echo -e "${CYAN}==========================================${PLAIN}"
echo -e "${CYAN}      Reality 最佳域名智能扫描助手 V1.0    ${PLAIN}"
echo -e "${CYAN}      自动避雷 | 智能优选 | 证书分级      ${PLAIN}"
echo -e "${CYAN}==========================================${PLAIN}"

# 1. 检查并下载工具
if [ ! -f "RealiTLScanner-linux-64" ]; then
    echo -e "${YELLOW}[*] 正在下载 RealiTLScanner 工具...${PLAIN}"
    wget -q -N https://github.com/XTLS/RealiTLScanner/releases/download/v0.2.1/RealiTLScanner-linux-64
    chmod +x RealiTLScanner-linux-64
    if [ ! -f "RealiTLScanner-linux-64" ]; then
        echo -e "${RED}[!] 下载失败，请检查网络或手动下载！${PLAIN}"
        exit 1
    fi
    echo -e "${GREEN}[+] 工具准备就绪。${PLAIN}"
else
    echo -e "${GREEN}[+] 检测到工具已存在，直接使用。${PLAIN}"
fi

# 2. 获取本机 IP 并计算网段
echo -e "${YELLOW}[*] 正在识别本机网络环境...${PLAIN}"
CURRENT_IP=$(curl -s4 ip.sb)
if [[ -z "$CURRENT_IP" ]]; then
    echo -e "${RED}[!] 无法获取本机 IP，请手动输入网段 (例如 47.236.105.0/24): ${PLAIN}"
    read -r SUBNET
else
    # 提取前三段，组装成 /24 网段
    SUBNET=$(echo "$CURRENT_IP" | awk -F. '{print $1"."$2"."$3".0/24"}')
    echo -e "${GREEN}[+] 识别到本机 IP: $CURRENT_IP${PLAIN}"
    echo -e "${GREEN}[+] 目标扫描网段: $SUBNET${PLAIN}"
fi

echo -e "${YELLOW}[*] 正在开始扫描... (请耐心等待约 10-20 秒)${PLAIN}"
echo -e "${YELLOW}[*] 正在过滤垃圾域名和危险目标...${PLAIN}"

# 3. 运行扫描并将结果存入临时文件
# 避雷关键词列表 (grep -v)
# CloudFlare, Kubernetes, Fake, Acme: 无效/自签名
# .cn, taobao, alibaba, baidu, qq, 163, byd: 中国特征太强/大厂
# .top, .xyz, .loan, .win, .shop: 垃圾域名后缀
./RealiTLScanner-linux-64 -addr "$SUBNET" -port 443 -thread 100 2>/dev/null | \
grep "feasible=true" | \
grep -v -E "CloudFlare|Kubernetes|Fake|Acme|Snake|localhost|internal" | \
grep -v -E "\.cn$|taobao|tmall|jd\.com|baidu|qq\.com|163\.com|aliyun|byd|huawei" | \
grep -v -E "\.top$|\.xyz$|\.loan$|\.win$|\.shop$|\.work$" > scan_results.txt

echo -e "${GREEN}[+] 扫描完成！正在进行智能分析...${PLAIN}"
echo -e "${CYAN}========================================================================${PLAIN}"
echo -e " 🏆  ${YELLOW}推荐等级${PLAIN} | ${BLUE}目标 IP (Dest)${PLAIN}      | ${GREEN}伪装域名 (SNI)${PLAIN}       | ${CYAN}证书机构${PLAIN}"
echo -e "${CYAN}========================================================================${PLAIN}"

# 4. 智能分析与排序展示
# 优先展示 DigiCert/Sectigo/GlobalSign (付费证书)
# 其次展示 Let's Encrypt (免费证书)

FOUND_COUNT=0

while read -r line; do
    # 提取关键信息
    IP=$(echo "$line" | grep -oP 'ip=\K[\d\.]+')
    DOMAIN=$(echo "$line" | grep -oP 'cert-domain=\K[^ ]+')
    ISSUER=$(echo "$line" | grep -oP 'cert-issuer="\K[^"]+')
    
    # 评分逻辑
    RANK="🥈 普通"
    COLOR=$PLAIN
    
    # 冠军逻辑：付费证书 + 常见后缀
    if [[ "$ISSUER" =~ "DigiCert" || "$ISSUER" =~ "Sectigo" || "$ISSUER" =~ "GlobalSign" || "$ISSUER" =~ "Entrust" || "$ISSUER" =~ "GeoTrust" ]]; then
        RANK="💎 极品"
        COLOR=$YELLOW  # 黄色高亮
    elif [[ "$ISSUER" =~ "Let's Encrypt" || "$ISSUER" =~ "ZeroSSL" ]]; then
        RANK="🥇 推荐"
        COLOR=$GREEN
    fi

    # 打印行
    printf " %b%-6s%b | %-20s | %-25s | %s\n" "$COLOR" "$RANK" "$PLAIN" "$IP:443" "$DOMAIN" "$ISSUER"
    ((FOUND_COUNT++))
    
    # 限制显示数量，防止刷屏，只显示前 15 个
    if [ "$FOUND_COUNT" -ge 15 ]; then
        break
    fi

# 先把付费证书的 grep 出来放在前面，再把其他的放在后面
done < <(cat scan_results.txt | grep -E "DigiCert|Sectigo|GlobalSign|Entrust" ; cat scan_results.txt | grep -v -E "DigiCert|Sectigo|GlobalSign|Entrust")

echo -e "${CYAN}========================================================================${PLAIN}"

if [ "$FOUND_COUNT" -eq 0 ]; then
    echo -e "${RED}[!] 没扫到合适的域名？可能是该网段质量太差。建议换个 IP 段或重新运行。${PLAIN}"
else
    echo -e "${YELLOW}💡 使用建议：${PLAIN}"
    echo -e "1. 优先选择 ${YELLOW}💎 极品${PLAIN} (付费证书)，信誉度最高，最像正经商业公司。"
    echo -e "2. 其次选择 ${GREEN}🥇 推荐${PLAIN} (Let's Encrypt)，这是最常见的正常网站。"
    echo -e "3. 填入配置时：Dest 填表格里的 IP，ServerName 填对应的域名。"
    echo -e "4. 本脚本已自动帮你排除了 Cloudflare、中国大厂、政府网站和垃圾后缀。"
fi

# 清理
rm -f scan_results.txt
