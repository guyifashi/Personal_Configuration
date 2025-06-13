#!/bin/bash
# sing-box TUN 模式管理脚本

CONFIG_FILE="$HOME/.config/sing-box/config.json"
LOG_FILE="$HOME/.config/sing-box/sing-box.log"
PID_FILE="$HOME/.config/sing-box/sing-box.pid"
LAUNCHD_PLIST="$HOME/Library/LaunchAgents/io.sagernet.sing-box.plist"
LAUNCHD_SYSTEM_PLIST="/Library/LaunchDaemons/io.sagernet.sing-box.plist"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 检查 sing-box 是否运行
is_running() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            return 0
        else
            rm -f "$PID_FILE"
            return 1
        fi
    fi
    return 1
}

# 检查是否有管理员权限
check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${YELLOW}⚠️  TUN 模式需要管理员权限${NC}"
        echo -e "${BLUE}💡 请输入密码以获取必要权限...${NC}"
        return 1
    fi
    return 0
}

# 检查 TUN 接口
check_tun() {
    echo -e "${BLUE}🔍 检查 TUN 接口状态...${NC}"
    
    # 检查是否有 TUN 接口
    if ifconfig | grep -q "utun"; then
        echo -e "${GREEN}✅ 发现 TUN 接口:${NC}"
        ifconfig | grep "utun" -A 3
        return 0
    else
        echo -e "${YELLOW}⚠️  未发现 TUN 接口${NC}"
        return 1
    fi
}

# 启动 sing-box
start() {
    if is_running; then
        echo -e "${YELLOW}sing-box 已经在运行中${NC}"
        return 1
    fi
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}配置文件不存在: $CONFIG_FILE${NC}"
        return 1
    fi
    
    echo -e "${BLUE}🚀 启动 sing-box (TUN 模式)...${NC}"
    
    # TUN 模式需要 sudo 权限
    if ! check_sudo; then
        echo -e "${CYAN}正在请求管理员权限...${NC}"
        sudo -v
        if [ $? -ne 0 ]; then
            echo -e "${RED}❌ 无法获取管理员权限${NC}"
            return 1
        fi
    fi
    
    # 后台启动 sing-box
    sudo nohup sing-box run -c "$CONFIG_FILE" > "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    
    sleep 3
    
    if is_running; then
        echo -e "${GREEN}✅ sing-box 启动成功${NC}"
        echo -e "${BLUE}📊 服务信息:${NC}"
        echo -e "   🌐 TUN 透明代理: 已启用"
        echo -e "   🧦 SOCKS5: 127.0.0.1:2333"
        echo -e "   🌍 HTTP: 127.0.0.1:2334"
        
        # 等待 TUN 接口创建
        sleep 2
        check_tun
        return 0
    else
        echo -e "${RED}❌ sing-box 启动失败${NC}"
        echo -e "${YELLOW}💡 请检查日志: singbox logs${NC}"
        return 1
    fi
}

# 停止 sing-box
stop() {
    if ! is_running; then
        echo -e "${YELLOW}sing-box 未运行${NC}"
        return 1
    fi
    
    echo -e "${BLUE}⏹️  停止 sing-box...${NC}"
    
    local pid=$(cat "$PID_FILE")
    sudo kill "$pid"
    
    # 等待进程结束
    local count=0
    while ps -p "$pid" > /dev/null 2>&1 && [ $count -lt 10 ]; do
        sleep 1
        count=$((count + 1))
    done
    
    if ps -p "$pid" > /dev/null 2>&1; then
        echo -e "${YELLOW}正常停止失败，强制终止...${NC}"
        sudo kill -9 "$pid"
    fi
    
    rm -f "$PID_FILE"
    echo -e "${GREEN}✅ sing-box 已停止${NC}"
}

# 重启 sing-box
restart() {
    echo -e "${BLUE}🔄 重启 sing-box...${NC}"
    stop
    sleep 2
    start
}

# 查看状态
status() {
    echo -e "${BLUE}📊 sing-box 状态检查:${NC}"
    
    if is_running; then
        local pid=$(cat "$PID_FILE")
        echo -e "${GREEN}✅ 运行中 (PID: $pid)${NC}"
        
        # 检查 TUN 接口
        echo -e "\n${BLUE}🌐 TUN 接口状态:${NC}"
        check_tun
        
        # 检查端口监听
        echo -e "\n${BLUE}📡 端口监听状态:${NC}"
        if lsof -i :2333 > /dev/null 2>&1; then
            echo -e "${GREEN}✅ SOCKS5 (2333) 正常${NC}"
        else
            echo -e "${RED}❌ SOCKS5 (2333) 异常${NC}"
        fi
        
        if lsof -i :2334 > /dev/null 2>&1; then
            echo -e "${GREEN}✅ HTTP (2334) 正常${NC}"
        else
            echo -e "${RED}❌ HTTP (2334) 异常${NC}"
        fi
        
        # 显示资源使用
        echo -e "\n${BLUE}💾 资源使用:${NC}"
        ps -p "$pid" -o pid,ppid,rss,vsz,pcpu,pmem,comm
        
        # 检查网络路由
        echo -e "\n${BLUE}🛣️  路由状态:${NC}"
        netstat -rn | grep -E "(default|0\.0\.0\.0)" | head -3
        
    else
        echo -e "${RED}❌ 未运行${NC}"
        
        # 检查 launchd 服务状态
        echo -e "\n${BLUE}🔍 检查自启动服务:${NC}"
        if [ -f "$LAUNCHD_PLIST" ]; then
            if launchctl list | grep -q "io.sagernet.sing-box"; then
                echo -e "${GREEN}✅ 用户级自启动服务已加载${NC}"
            else
                echo -e "${YELLOW}⚠️  用户级自启动服务未加载${NC}"
            fi
        elif [ -f "$LAUNCHD_SYSTEM_PLIST" ]; then
            if sudo launchctl list | grep -q "io.sagernet.sing-box"; then
                echo -e "${GREEN}✅ 系统级自启动服务已加载${NC}"
            else
                echo -e "${YELLOW}⚠️  系统级自启动服务未加载${NC}"
            fi
        else
            echo -e "${CYAN}ℹ️  未配置自启动服务${NC}"
        fi
    fi
}

# 测试连接
test_connection() {
    echo -e "${BLUE}🧪 测试网络连接...${NC}"
    
    if ! is_running; then
        echo -e "${RED}❌ sing-box 未运行，无法测试${NC}"
        return 1
    fi
    
    # 测试透明代理（TUN 模式）
    echo -e "\n${BLUE}🌐 测试透明代理:${NC}"
    if curl https://ipinfo.io/ip --max-time 10 -s > /tmp/tun_ip 2>/dev/null; then
        local tun_ip=$(cat /tmp/tun_ip)
        echo -e "${GREEN}✅ 透明代理工作正常，IP: $tun_ip${NC}"
        rm -f /tmp/tun_ip
    else
        echo -e "${RED}❌ 透明代理连接失败${NC}"
    fi
    
    # 测试 SOCKS5
    echo -e "\n${BLUE}🧦 测试 SOCKS5 代理:${NC}"
    if curl --socks5 127.0.0.1:2333 https://ipinfo.io/ip --max-time 10 -s | grep -q "\."; then
        echo -e "${GREEN}✅ SOCKS5 代理工作正常${NC}"
    else
        echo -e "${RED}❌ SOCKS5 代理连接失败${NC}"
    fi
    
    # 测试分流
    echo -e "\n${BLUE}🎯 测试智能分流:${NC}"
    echo -e "${CYAN}测试国内网站 (应该直连):${NC}"
    if curl https://baidu.com -I --max-time 5 -s | grep -q "200 OK"; then
        echo -e "${GREEN}✅ 国内网站访问正常${NC}"
    else
        echo -e "${YELLOW}⚠️  国内网站访问异常${NC}"
    fi
    
    echo -e "${CYAN}测试国外网站 (应该走代理):${NC}"
    if curl https://google.com -I --max-time 10 -s | grep -q "200 OK"; then
        echo -e "${GREEN}✅ 国外网站访问正常${NC}"
    else
        echo -e "${YELLOW}⚠️  国外网站访问异常${NC}"
    fi
}

# 创建 launchd 服务
create_launchd() {
    local service_type="$1"
    local username=$(whoami)
    
    if [ "$service_type" = "system" ]; then
        echo -e "${BLUE}🔧 创建系统级 launchd 服务 (推荐)...${NC}"
        
        # 创建系统级服务文件
        sudo tee "$LAUNCHD_SYSTEM_PLIST" > /dev/null << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>io.sagernet.sing-box</string>
    <key>ProgramArguments</key>
    <array>
        <string>$(which sing-box)</string>
        <string>run</string>
        <string>-c</string>
        <string>$CONFIG_FILE</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>StandardErrorPath</key>
    <string>/var/log/sing-box.error.log</string>
    <key>StandardOutPath</key>
    <string>/var/log/sing-box.out.log</string>
    <key>UserName</key>
    <string>root</string>
    <key>GroupName</key>
    <string>wheel</string>
    <key>WorkingDirectory</key>
    <string>/var/root</string>
</dict>
</plist>
EOF
        
        # 加载服务
        sudo launchctl load "$LAUNCHD_SYSTEM_PLIST"
        echo -e "${GREEN}✅ 系统级自启动服务已创建并启动${NC}"
        
    else
        echo -e "${BLUE}🔧 创建用户级 launchd 服务...${NC}"
        
        # 确保目录存在
        mkdir -p "$(dirname "$LAUNCHD_PLIST")"
        
        # 创建用户级服务文件
        tee "$LAUNCHD_PLIST" > /dev/null << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>io.sagernet.sing-box</string>
    <key>ProgramArguments</key>
    <array>
        <string>$(which sing-box)</string>
        <string>run</string>
        <string>-c</string>
        <string>$CONFIG_FILE</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>StandardErrorPath</key>
    <string>$LOG_FILE</string>
    <key>StandardOutPath</key>
    <string>$LOG_FILE</string>
    <key>WorkingDirectory</key>
    <string>$HOME</string>
</dict>
</plist>
EOF
        
        # 加载服务
        launchctl load "$LAUNCHD_PLIST"
        echo -e "${GREEN}✅ 用户级自启动服务已创建并启动${NC}"
        echo -e "${YELLOW}⚠️  注意: 用户级服务可能无法创建 TUN 接口${NC}"
    fi
}

# 移除 launchd 服务
remove_launchd() {
    echo -e "${BLUE}🗑️  移除自启动服务...${NC}"
    
    # 检查并移除系统级服务
    if [ -f "$LAUNCHD_SYSTEM_PLIST" ]; then
        sudo launchctl unload "$LAUNCHD_SYSTEM_PLIST" 2>/dev/null
        sudo rm -f "$LAUNCHD_SYSTEM_PLIST"
        echo -e "${GREEN}✅ 系统级自启动服务已移除${NC}"
    fi
    
    # 检查并移除用户级服务
    if [ -f "$LAUNCHD_PLIST" ]; then
        launchctl unload "$LAUNCHD_PLIST" 2>/dev/null
        rm -f "$LAUNCHD_PLIST"
        echo -e "${GREEN}✅ 用户级自启动服务已移除${NC}"
    fi
    
    if [ ! -f "$LAUNCHD_SYSTEM_PLIST" ] && [ ! -f "$LAUNCHD_PLIST" ]; then
        echo -e "${YELLOW}ℹ️  未发现自启动服务${NC}"
    fi
}

# 显示帮助
help() {
    echo -e "${BLUE}sing-box TUN 模式管理脚本${NC}"
    echo -e "\n${BLUE}用法:${NC}"
    echo -e "  $0 {start|stop|restart|status|logs|follow|test|autostart|remove-autostart|help}"
    echo -e "\n${BLUE}命令说明:${NC}"
    echo -e "  ${GREEN}start${NC}             - 启动 sing-box (需要管理员权限)"
    echo -e "  ${GREEN}stop${NC}              - 停止 sing-box"
    echo -e "  ${GREEN}restart${NC}           - 重启 sing-box"
    echo -e "  ${GREEN}status${NC}            - 查看运行状态和网络信息"
    echo -e "  ${GREEN}logs${NC}              - 查看日志"
    echo -e "  ${GREEN}follow${NC}            - 实时查看日志"
    echo -e "  ${GREEN}test${NC}              - 测试连接和分流"
    echo -e "  ${GREEN}autostart${NC}         - 配置开机自启动"
    echo -e "  ${GREEN}remove-autostart${NC}  - 移除开机自启动"
    echo -e "  ${GREEN}help${NC}              - 显示帮助"
    
    echo -e "\n${BLUE}TUN 模式说明:${NC}"
    echo -e "  🌐 透明代理 - 无需手动设置浏览器代理"
    echo -e "  🔒 需要管理员权限创建 TUN 接口"
    echo -e "  🚀 最佳用户体验 - 自动代理所有应用"
    
    echo -e "\n${BLUE}自启动说明:${NC}"
    echo -e "  💡 推荐使用系统级自启动 (需要管理员权限)"
    echo -e "  ⚠️  用户级自启动可能无法创建 TUN 接口"
}

# 查看日志
logs() {
    if [ -f "$LOG_FILE" ]; then
        echo -e "${BLUE}📋 sing-box 日志 (最后20行):${NC}"
        tail -20 "$LOG_FILE"
    else
        echo -e "${YELLOW}日志文件不存在${NC}"
    fi
}

# 实时查看日志
logs_follow() {
    if [ -f "$LOG_FILE" ]; then
        echo -e "${BLUE}📋 实时查看 sing-box 日志 (Ctrl+C 退出):${NC}"
        tail -f "$LOG_FILE"
    else
        echo -e "${YELLOW}日志文件不存在${NC}"
    fi
}

# 主函数
case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        restart
        ;;
    status)
        status
        ;;
    logs)
        logs
        ;;
    follow)
        logs_follow
        ;;
    test)
        test_connection
        ;;
    autostart)
        echo -e "${BLUE}选择自启动类型:${NC}"
        echo -e "1. 系统级 (推荐，需要管理员权限)"
        echo -e "2. 用户级 (可能无法创建 TUN 接口)"
        read -p "请选择 (1/2): " choice
        case $choice in
            1) create_launchd "system" ;;
            2) create_launchd "user" ;;
            *) echo -e "${RED}无效选择${NC}" ;;
        esac
        ;;
    remove-autostart)
        remove_launchd
        ;;
    help|--help|-h)
        help
        ;;
    *)
        echo -e "${RED}未知命令: $1${NC}"
        help
        exit 1
        ;;
esac