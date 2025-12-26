#!/bin/bash

# Moments 交互式一键部署脚本
# 功能：通过交互式界面收集配置信息，生成 .env 文件并启动服务

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 清屏
clear

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}  Moments 交互式一键部署脚本${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

# 检查 Docker 是否安装
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ 错误: 未安装 Docker，请先安装 Docker${NC}"
    exit 1
fi

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo -e "${RED}❌ 错误: 未安装 Docker Compose，请先安装 Docker Compose${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Docker 环境检查通过${NC}"
echo ""

# 检查是否已存在 .env 文件
if [ -f ".env" ]; then
    echo -e "${YELLOW}⚠️  检测到已存在 .env 文件${NC}"
    read -p "是否覆盖现有配置？(y/n，默认n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}已取消，使用现有配置启动服务${NC}"
        docker-compose up -d
        exit 0
    fi
    echo ""
fi

# ==================== 收集配置信息 ====================

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  开始配置 Moments 部署参数${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 1. 服务器配置
echo -e "${BLUE}📡 服务器配置${NC}"
echo ""

read -p "服务端口 (默认: 8030): " SERVER_PORT
SERVER_PORT=${SERVER_PORT:-8030}

# 验证端口是否为数字
if ! [[ "$SERVER_PORT" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}❌ 端口必须是数字，使用默认值 8030${NC}"
    SERVER_PORT=8030
fi

read -p "服务器模式 [debug/release/test] (默认: release): " SERVER_MODE
SERVER_MODE=${SERVER_MODE:-release}
if [[ ! "$SERVER_MODE" =~ ^(debug|release|test)$ ]]; then
    echo -e "${YELLOW}⚠️  无效的模式，使用默认值 release${NC}"
    SERVER_MODE=release
fi

echo ""

# 2. 数据库配置
echo -e "${BLUE}🗄️  数据库配置${NC}"
echo ""

read -p "是否使用 Docker Compose 内置的 MySQL？(y/n，默认y): " -n 1 -r USE_BUILTIN_MYSQL
echo ""
USE_BUILTIN_MYSQL=${USE_BUILTIN_MYSQL:-y}

if [[ $USE_BUILTIN_MYSQL =~ ^[Yy]$ ]]; then
    # 使用内置 MySQL
    DB_HOST="mysql"
    DB_PORT="3306"
    
    echo ""
    echo -e "${GREEN}✅ 将使用 Docker Compose 内置的 MySQL 服务${NC}"
    echo ""
    
    read -p "MySQL root 密码 (默认: moments123456): " DB_PASSWORD
    DB_PASSWORD=${DB_PASSWORD:-moments123456}
    
    read -p "数据库名称 (默认: moments): " DB_NAME
    DB_NAME=${DB_NAME:-moments}
    
    DB_USER="root"
    
    echo ""
    read -p "MySQL 外部访问端口 (留空则不暴露，默认: 3307): " MYSQL_EXTERNAL_PORT
    MYSQL_EXTERNAL_PORT=${MYSQL_EXTERNAL_PORT:-3307}
    
    if [ -z "$MYSQL_EXTERNAL_PORT" ]; then
        MYSQL_EXTERNAL_PORT=""
    fi
else
    # 使用外部数据库
    echo ""
    echo -e "${YELLOW}⚠️  将使用外部 MySQL 数据库${NC}"
    echo ""
    
    read -p "数据库主机地址: " DB_HOST
    if [ -z "$DB_HOST" ]; then
        echo -e "${RED}❌ 数据库主机地址不能为空${NC}"
        exit 1
    fi
    
    read -p "数据库端口 (默认: 3306): " DB_PORT
    DB_PORT=${DB_PORT:-3306}
    
    read -p "数据库用户名: " DB_USER
    if [ -z "$DB_USER" ]; then
        echo -e "${RED}❌ 数据库用户名不能为空${NC}"
        exit 1
    fi
    
    read -sp "数据库密码: " DB_PASSWORD
    echo ""
    if [ -z "$DB_PASSWORD" ]; then
        echo -e "${RED}❌ 数据库密码不能为空${NC}"
        exit 1
    fi
    
    read -p "数据库名称 (默认: moments): " DB_NAME
    DB_NAME=${DB_NAME:-moments}
    
    MYSQL_EXTERNAL_PORT=""
fi

echo ""

# 3. JWT 配置
echo -e "${BLUE}🔐 JWT 配置${NC}"
echo ""

read -sp "JWT Secret (至少32字符，留空将自动生成): " JWT_SECRET
echo ""

if [ -z "$JWT_SECRET" ]; then
    # 自动生成随机密钥（64字符）
    JWT_SECRET=$(openssl rand -hex 32 2>/dev/null || cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 64 | head -n 1)
    echo -e "${GREEN}✅ 已自动生成 JWT Secret${NC}"
else
    if [ ${#JWT_SECRET} -lt 32 ]; then
        echo -e "${YELLOW}⚠️  警告: JWT Secret 长度少于32字符，建议使用更长的密钥${NC}"
        read -p "是否继续？(y/n，默认y): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]] && [ -n "$REPLY" ]; then
            echo "已取消部署"
            exit 1
        fi
    fi
fi

read -p "JWT 过期时间（小时，默认: 168，即7天）: " JWT_EXPIRE_HOURS
JWT_EXPIRE_HOURS=${JWT_EXPIRE_HOURS:-168}

if ! [[ "$JWT_EXPIRE_HOURS" =~ ^[0-9]+$ ]]; then
    echo -e "${YELLOW}⚠️  无效的数字，使用默认值 168${NC}"
    JWT_EXPIRE_HOURS=168
fi

echo ""

# 4. 其他配置（可选）
echo -e "${BLUE}⚙️  其他配置（可选）${NC}"
echo ""

read -p "POST_PASSWORD_SALT (留空则跳过): " POST_PASSWORD_SALT
read -p "POST_TOKEN_SECRET (留空则跳过): " POST_TOKEN_SECRET

echo ""

# ==================== 显示配置摘要 ====================

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  配置摘要${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${GREEN}服务器配置:${NC}"
echo -e "    端口: ${YELLOW}${SERVER_PORT}${NC}"
echo -e "    模式: ${YELLOW}${SERVER_MODE}${NC}"
echo ""
echo -e "  ${GREEN}数据库配置:${NC}"
echo -e "    主机: ${YELLOW}${DB_HOST}${NC}"
echo -e "    端口: ${YELLOW}${DB_PORT}${NC}"
echo -e "    用户: ${YELLOW}${DB_USER}${NC}"
echo -e "    密码: ${YELLOW}${DB_PASSWORD:0:3}***${NC}"
echo -e "    数据库: ${YELLOW}${DB_NAME}${NC}"
if [ -n "$MYSQL_EXTERNAL_PORT" ]; then
    echo -e "    MySQL外部端口: ${YELLOW}${MYSQL_EXTERNAL_PORT}${NC}"
fi
echo ""
echo -e "  ${GREEN}JWT 配置:${NC}"
echo -e "    Secret: ${YELLOW}${JWT_SECRET:0:20}...${NC}"
echo -e "    过期时间: ${YELLOW}${JWT_EXPIRE_HOURS} 小时${NC}"
echo ""

read -p "确认以上配置并开始部署？(y/n，默认y): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]] && [ -n "$REPLY" ]; then
    echo -e "${YELLOW}已取消部署${NC}"
    exit 0
fi

echo ""

# ==================== 生成 .env 文件 ====================

echo -e "${BLUE}📝 生成配置文件...${NC}"

cat > .env <<EOF
# Moments Docker 部署环境变量配置
# 由交互式部署脚本自动生成于 $(date '+%Y-%m-%d %H:%M:%S')

# ==================== 数据库配置 ====================
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
DB_NAME=${DB_NAME}

# ==================== 服务器配置 ====================
SERVER_HOST=0.0.0.0
SERVER_PORT=${SERVER_PORT}
SERVER_MODE=${SERVER_MODE}

# ==================== JWT配置 ====================
JWT_SECRET=${JWT_SECRET}
JWT_EXPIRE_HOURS=${JWT_EXPIRE_HOURS}

# ==================== MySQL 外部端口（可选）====================
EOF

if [ -n "$MYSQL_EXTERNAL_PORT" ]; then
    echo "MYSQL_EXTERNAL_PORT=${MYSQL_EXTERNAL_PORT}" >> .env
fi

cat >> .env <<EOF

# ==================== 其他配置 ====================
EOF

if [ -n "$POST_PASSWORD_SALT" ]; then
    echo "POST_PASSWORD_SALT=${POST_PASSWORD_SALT}" >> .env
fi

if [ -n "$POST_TOKEN_SECRET" ]; then
    echo "POST_TOKEN_SECRET=${POST_TOKEN_SECRET}" >> .env
fi

echo -e "${GREEN}✅ 配置文件已生成: .env${NC}"
echo ""

# ==================== 检查并更新 docker-compose.yml 端口映射 ====================

if [ "$SERVER_PORT" != "8030" ]; then
    echo -e "${YELLOW}⚠️  检测到端口不是默认值 8030${NC}"
    echo -e "${YELLOW}   需要更新 docker-compose.yml 中的端口映射${NC}"
    read -p "是否自动更新 docker-compose.yml？(y/n，默认y): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]] || [ -z "$REPLY" ]; then
        # 检查系统类型，使用不同的 sed 命令
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            sed -i '' "s|\"\${SERVER_PORT:-8030}:8030\"|\"${SERVER_PORT}:8030\"|g" docker-compose.yml
        else
            # Linux
            sed -i "s|\"\${SERVER_PORT:-8030}:8030\"|\"${SERVER_PORT}:8030\"|g" docker-compose.yml
        fi
        echo -e "${GREEN}✅ 已更新 docker-compose.yml 端口映射${NC}"
    else
        echo -e "${YELLOW}⚠️  请手动修改 docker-compose.yml 中的端口映射${NC}"
    fi
    echo ""
fi

# ==================== 启动服务 ====================

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  开始部署服务${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${BLUE}📥 拉取最新镜像并启动服务...${NC}"
echo ""

# 如果使用外部数据库，需要检查 docker-compose.yml 是否需要修改
if [[ ! $USE_BUILTIN_MYSQL =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}⚠️  您选择了使用外部数据库${NC}"
    echo -e "${YELLOW}   请确保 docker-compose.yml 中已移除或注释掉 mysql 服务${NC}"
    echo ""
    read -p "是否继续？(y/n，默认y): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]] && [ -n "$REPLY" ]; then
        echo -e "${YELLOW}已取消部署${NC}"
        exit 0
    fi
fi

# 拉取最新镜像
echo -e "${BLUE}📥 拉取 Docker 镜像...${NC}"
docker-compose pull moments

# 启动服务
echo -e "${BLUE}🚀 启动服务...${NC}"
docker-compose up -d

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ 服务启动成功！${NC}"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  部署完成${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${GREEN}📍 访问地址:${NC}"
    echo -e "   前端界面: ${YELLOW}http://localhost:${SERVER_PORT}${NC}"
    echo -e "   API 接口: ${YELLOW}http://localhost:${SERVER_PORT}/api${NC}"
    echo -e "   健康检查: ${YELLOW}http://localhost:${SERVER_PORT}/health${NC}"
    echo ""
    echo -e "${GREEN}📋 常用命令:${NC}"
    echo -e "   查看日志: ${YELLOW}docker-compose logs -f${NC}"
    echo -e "   查看状态: ${YELLOW}docker-compose ps${NC}"
    echo -e "   停止服务: ${YELLOW}docker-compose down${NC}"
    echo -e "   重启服务: ${YELLOW}docker-compose restart${NC}"
    echo ""
    echo -e "${YELLOW}💡 提示:${NC}"
    echo -e "   配置文件已保存到: ${CYAN}.env${NC}"
    echo -e "   可以随时编辑此文件修改配置"
    echo ""
else
    echo ""
    echo -e "${RED}❌ 服务启动失败${NC}"
    echo ""
    echo -e "${YELLOW}请检查:${NC}"
    echo -e "   1. Docker 服务是否正常运行"
    echo -e "   2. 端口 ${SERVER_PORT} 是否被占用"
    echo -e "   3. 查看详细日志: docker-compose logs"
    echo ""
    exit 1
fi

