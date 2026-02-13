#!/bin/bash

# ==========================================
# 颜色定义
# ==========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# ==========================================
# 1. 初始化检查
# ==========================================
clear
echo -e "${CYAN}==========================================${PLAIN}"
echo -e "${CYAN}      Reality 最佳域名智能扫描助手 V2.0    ${PLAIN}"
echo -e "${CYAN}      动态进度 | 实时计数 | 智能避雷      ${PLAIN}"
echo -e "${CYAN}==========================================${PLAIN}"

if [ ! -f "RealiTLScanner-linux-64" ]; then
    echo -e "${YELLOW}[*] 正在下载 RealiTLScanner 工具...${PLAIN}"
    wget -q -N https://github.com/XTLS/RealiTLScanner/releases/download/v0.2.1/RealiTLScanner-linux-64
    chmod +x RealiTLScanner-linux-64
    if [ ! -f "RealiTLScanner-linux-64" ]; then
        echo -e "${RED}[!] 下载失败，请检查网络或手动下载！${PLAIN}"
        exit 1
    fi
    echo -e "${GREEN}[+] 工具下载完成。${PLAIN}"
else
    echo -e "${GREEN}[+] 检测到工具已存在，直接使用。${PLAIN}"
fi

# ==========================================
# 2. 获取网络环境
# ==========================================
echo -e "${YELLOW}[*] 正在识别本机网络环境...${PLAIN}"
CURRENT_IP=$(curl -s4 ip.sb)
if [[ -z "$CURRENT_IP" ]]; then
    echo -e "${RED}[!] 无法自动获取 IP，请输入扫描网段 (如 47.236.105.0/24): ${PLAIN}"
    read -r SUBNET
else
    # 提取前三段，组装成 /24 网段
    SUBNET=$(echo "$CURRENT_IP" | awk -F. '{print $1"."$2"."$3".0/24"}')
    echo -e "${GREEN}[+] 识别到本机 IP: $CURRENT_IP${PLAIN}"
    echo -e "${GREEN}[+] 目标扫描网段: $SUBNET${PLAIN}"
fi

# ==========================================
# 3. 开始扫描 (后台运行 + 前台动画)
# ==========================================
echo -e "${YELLOW}[*] 正在启动扫描进程...${PLAIN}"

# 将输出重定向到临时文件，放入后台运行
./RealiTLScanner-linux-64 -addr "$SUBNET" -port 443 -thread 100 > scan_temp.log 2>&1 &
PID=$! # 获取扫描进程的 PID

# 动画循环
spin='-\|/'
i=0
while kill -0 $PID 2>/dev/null; do
    i=$(( (i+1) %4 ))
    
    # 实时统计已发现的“可行”目标数量
    if [ -f scan_temp.log ]; then
        count=$(grep -c "feasible=true" scan_temp.log)
    else
        count=0
    fi
    
    # \r 让光标回到行首，实现原地刷新
    printf "\r${YELLOW}[*] 正在扫描中... ${spin:$i:1} [已发现潜在目标: ${GREEN}$count${YELLOW}]${PLAIN}"
    sleep 0.1
done

# 换行，防止下一行文字覆盖
echo ""
echo -e "${GREEN}[+] 扫描结束！正在进行智能过滤与分析...${PLAIN}"

# ==========================================
# 4. 过滤与结果处理
# ==========================================

# 避雷关键词列表
# CloudFlare, Kubernetes, Fake, Acme: 无效/自签名
# .cn, taobao, alibaba, baidu, qq, 163, byd: 中国特征太强/大厂
# .top, .xyz, .loan, .win, .shop, .work: 垃圾域名后缀
cat scan_temp.log | \
grep "feasible=true" | \
grep -v -E "CloudFlare|Kubernetes|Fake|Acme|Snake|localhost|internal" | \
grep -v -E "\.cn$|taobao|tmall|jd\.com|baidu|qq\.com|163\.com|aliyun|byd|huawei" | \
grep -v -E "\.top$|\.xyz$|\.loan$|\.win$|\.shop$|\.work$" > scan_results.txt

echo -e "${CYAN}========================================================================${PLAIN}"
echo -e " 🏆  ${YELLOW}推荐等级${PLAIN} | ${BLUE}目标 IP (Dest)${PLAIN}      | ${GREEN}伪装域名 (SNI)${PLAIN}       | ${CYAN}证书机构${PLAIN}"
echo -e "${CYAN}========================================================================${PLAIN}"

# ==========================================
# 5. 智能排序与显示
# ==========================================

FOUND_COUNT=0

# 分两次读取：先显示付费证书(极品)，再显示免费证书(普通)
# 这里利用临时文件排序技巧
cat scan_results.txt | grep -E "DigiCert|Sectigo|GlobalSign|Entrust|GeoTrust" > sorted_results.txt
cat scan_results.txt | grep -v -E "DigiCert|Sectigo|GlobalSign|Entrust|GeoTrust" >> sorted_results.txt

while read -r line; do
    # 提取关键信息
    IP=$(echo "$line" | grep -oP 'ip=\K[\d\.]+')
    DOMAIN=$(echo "$line" | grep -oP 'cert-domain=\K[^ ]+')
    ISSUER=$(echo "$line" | grep -oP 'cert-issuer="\K[^"]+')
    
    if [[ -z "$IP" ]]; then continue; fi

    # 评分逻辑
    RANK="🥈 普通"
    COLOR=$PLAIN
    
    # 冠军逻辑：付费证书
    if [[ "$ISSUER" =~ "DigiCert" || "$ISSUER" =~ "Sectigo" || "$ISSUER" =~ "GlobalSign" || "$ISSUER" =~ "Entrust" || "$ISSUER" =~ "GeoTrust" ]]; then
        RANK="💎 极品"
        COLOR=$YELLOW  # 黄色高亮
    elif [[ "$ISSUER" =~ "Let's Encrypt" || "$ISSUER" =~ "ZeroSSL" ]]; then
        RANK="🥇 推荐"
        COLOR=$GREEN
    fi

    # 格式化打印
    printf " %b%-6s%b | %-20s | %-25s | %s\n" "$COLOR" "$RANK" "$PLAIN" "$IP:443" "$DOMAIN" "$ISSUER"
    ((FOUND_COUNT++))
    
    # 只显示前 20 个，避免刷屏
    if [ "$FOUND_COUNT" -ge 20 ]; then
        break
    fi

done < sorted_results.txt

echo -e "${CYAN}========================================================================${PLAIN}"

if [ "$FOUND_COUNT" -eq 0 ]; then
    echo -e "${RED}[!] 很遗憾，未找到符合严选标准的目标。${PLAIN}"
    echo -e "${RED}[!] 原扫描日志中有 $(grep -c "feasible=true" scan_temp.log) 个目标，但都被安全策略过滤了。${PLAIN}"
else
    echo -e "${YELLOW}💡 选购指南：${PLAIN}"
    echo -e "1. 闭眼选 ${YELLOW}💎 极品${PLAIN}，通常是企业付费证书，最稳。"
    echo -e "2. 填入配置时：Dest 填 IP，ServerName 填域名。"
fi

# 清理临时文件
rm -f scan_temp.log scan_results.txt sorted_results.txt
