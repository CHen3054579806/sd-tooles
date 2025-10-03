#!/bin/bash
# Steam Deck工具箱（密码修复终极版+开发者模式+GitHub自动更新）
# 安全说明：脚本已通过shc混淆，禁止倒卖，违者必究
# -------------------------- 新增：自动更新配置 --------------------------
# 1. 本地脚本版本（需与GitHub仓库版本同步更新）
LOCAL_VERSION="1.0.2"  # 已更新到1.0.2版本
# 2. GitHub仓库信息（已匹配你的仓库）
GITHUB_REPO_OWNER="CHen3054579806"
GITHUB_REPO_NAME="sd-tooles"
GITHUB_BRANCH="main"
# 3. GitHub上脚本的原始文件URL
GITHUB_SCRIPT_URL="https://raw.githubusercontent.com/$GITHUB_REPO_OWNER/$GITHUB_REPO_NAME/$GITHUB_BRANCH/$(basename "$0")"
# 4. 备份文件后缀（更新失败时恢复）
BACKUP_SUFFIX=".backup_$(date +%Y%m%d%H%M%S)"

# 系统常量（保持不变）
EXTENSIONS_DIR="$HOME/.steam_deck_toolbox/extensions"
EXTENSIONS_INDEX="$HOME/.steam_deck_toolbox/extensions/index.csv"
PASSWORD_STORE="$HOME/.config/steam_deck_toolbox"
PASSWORD_FILE="$PASSWORD_STORE/sudo_pass"
DEV_MODE_FLAG="$PASSWORD_STORE/dev_mode_enabled"
MAIN_MENU_CONFIG="$PASSWORD_STORE/main_menu_config.csv"
mkdir -p "$EXTENSIONS_DIR"
mkdir -p "$PASSWORD_STORE"

# 安全终端重置（保持不变）
safe_terminal_reset() {
    stty sane
    echo -ne "\033c"
    tput reset 2>/dev/null
    clear
}

# -------------------------- 新增：自动更新核心函数（修复版） --------------------------
# 1. 检查依赖（curl是更新必需的）
check_update_deps() {
    if ! command -v curl &> /dev/null; then
        dialog --infobox "正在安装更新必需组件（curl）..." 6 40
        local temp_pass=$(get_password "需要临时权限" "安装更新组件curl需管理员密码")
        [ -z "$temp_pass" ] && { dialog --msgbox "未获取权限，无法安装curl，更新功能禁用" 6 40; return 1; }
        echo "$temp_pass" | sudo -S pacman -S --noconfirm curl >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            dialog --msgbox "curl安装失败，无法使用自动更新" 6 40
            return 1
        fi
    fi
    return 0
}

# 2. 获取GitHub最新版本（优先读Release Tag，失败则读分支内的VERSION文件）
get_github_latest_version() {
    local timeout=10
    # 方式1：从GitHub Release获取最新Tag
    local latest_version=$(curl -s --max-time $timeout "https://api.github.com/repos/$GITHUB_REPO_OWNER/$GITHUB_REPO_NAME/releases/latest" | grep -o '"tag_name": ".*"' | sed 's/"tag_name": "//;s/"//')

    # 方式2：从分支内的VERSION文件读取
    if [ -z "$latest_version" ] || [ "$latest_version" = "null" ]; then
        latest_version=$(curl -s --max-time $timeout "https://raw.githubusercontent.com/$GITHUB_REPO_OWNER/$GITHUB_REPO_NAME/$GITHUB_BRANCH/VERSION")
    fi

    # 清理版本号（移除可能的前缀v）
    latest_version=$(echo "$latest_version" | sed 's/^v//')
    echo "$latest_version"
}

# 3. 语义化版本对比（判断是否需要更新：返回1需更新，0无需更新，-1对比失败）
compare_versions() {
    local local_ver="$1"
    local github_ver="$2"

    # 版本号格式不合法（如非x.y.z）直接返回失败
    if ! echo "$local_ver" | grep -q '^[0-9]\+\.[0-9]\+\.[0-9]\+$' || ! echo "$github_ver" | grep -q '^[0-9]\+\.[0-9]\+\.[0-9]\+$'; then
        return -1
    fi

    # 拆分版本号为数组（主版本.次版本.修订号）
    IFS='.' read -r l1 l2 l3 <<< "$local_ver"
    IFS='.' read -r g1 g2 g3 <<< "$github_ver"

    # 对比主版本→次版本→修订号
    if [ "$g1" -gt "$l1" ]; then return 1; fi
    if [ "$g1" -lt "$l1" ]; then return 0; fi
    if [ "$g2" -gt "$l2" ]; then return 1; fi
    if [ "$g2" -lt "$l2" ]; then return 0; fi
    if [ "$g3" -gt "$l3" ]; then return 1; fi
    return 0
}

# 4. 执行自动更新（核心函数，增加错误处理）
auto_update() {
    # 检查脚本是否有写入权限
    if [ ! -w "$0" ]; then
        dialog --msgbox "脚本文件没有写入权限，无法更新\n请执行: chmod +w $(realpath "$0")" 6 50
        return 1
    fi

    # 步骤1：检查更新依赖（curl）
    dialog --infobox "正在检查更新环境..." 6 40
    if ! check_update_deps; then
        return 1
    fi

    # 步骤2：获取本地版本和GitHub最新版本
    dialog --infobox "正在检查最新版本..." 6 40
    local github_version=$(get_github_latest_version)

    # 校验GitHub版本是否有效
    if [ -z "$github_version" ] || [ "$github_version" = "null" ]; then
        dialog --msgbox "获取GitHub版本失败\n可能原因：\n1. 网络连接问题\n2. 仓库配置错误\n3. 未发布Release且无VERSION文件" 10 60
        return 1
    fi

    # 步骤3：对比版本，判断是否需要更新
    compare_versions "$LOCAL_VERSION" "$github_version"
    local compare_result=$?
    if [ $compare_result -eq 0 ]; then
        dialog --msgbox "当前已是最新版本（v$LOCAL_VERSION）" 6 40
        return 0
    elif [ $compare_result -eq -1 ]; then
        dialog --msgbox "版本格式错误（本地：v$LOCAL_VERSION，GitHub：v$github_version）" 6 40
        return 1
    fi

    # 步骤4：提示用户是否更新
    dialog --yesno "发现新版本：v$github_version（当前：v$LOCAL_VERSION）\n是否立即更新？" 8 40
    if [ $? -ne 0 ]; then
        dialog --msgbox "已取消更新" 6 40
        return 0
    fi

    # 步骤5：备份本地脚本（防止更新失败）
    dialog --infobox "正在备份当前脚本..." 6 40
    local backup_file="$0$BACKUP_SUFFIX"
    cp "$0" "$backup_file" 2>/dev/null
    if [ $? -ne 0 ]; then
        dialog --msgbox "脚本备份失败，无法更新" 6 40
        return 1
    fi

    # 步骤6：下载最新脚本并替换（增加详细错误输出）
    dialog --infobox "正在下载新版本（v$github_version）..." 6 40
    curl -L --show-error --fail "$GITHUB_SCRIPT_URL" -o "$0.tmp" 2>/tmp/update_error.log

    # 校验下载文件是否有效（非空且是bash脚本）
    if [ ! -s "$0.tmp" ] || ! grep -q "#!/bin/bash" "$0.tmp" 2>/dev/null; then
        local error_log=$(cat /tmp/update_error.log)
        dialog --msgbox "下载失败！错误信息：\n$error_log\n已恢复原脚本\n\n请检查：\n1. GitHub仓库地址是否正确\n2. 网络连接是否正常\n3. 脚本文件名是否一致" 12 60
        mv "$backup_file" "$0" 2>/dev/null  # 恢复备份
        rm -f "$0.tmp" /tmp/update_error.log
        return 1
    fi

    # 步骤7：替换脚本并添加执行权限
    chmod +x "$0.tmp"  # 确保新脚本可执行
    mv "$0.tmp" "$0" 2>/dev/null
    if [ $? -ne 0 ]; then
        dialog --msgbox "更新替换失败，已恢复原脚本" 6 40
        mv "$backup_file" "$0" 2>/dev/null
        return 1
    fi

    # 步骤8：提示更新成功并重启脚本
    dialog --msgbox "更新成功！已升级至v$github_version\n脚本将自动重启" 6 40
    rm -f /tmp/update_error.log  # 清理临时文件
    exec "$0" "$@"  # 重启脚本，应用新版本
}

# 密码存储核心函数（保持不变）
save_password() {
    local pass="$1"
    echo -n "$pass" | base64 > "$PASSWORD_FILE"
    chmod 600 "$PASSWORD_FILE"
}

# 密码读取核心函数（保持不变）
load_password() {
    if [ ! -f "$PASSWORD_FILE" ]; then
        return 1
    fi
    local pass=$(cat "$PASSWORD_FILE" | base64 -d 2>/dev/null)
    if [ -n "$pass" ]; then
        echo "$pass"
        return 0
    fi
    return 1
}

# 通用密码输入函数（带可视/不可视切换）
get_password() {
    local title="$1"
    local message="$2"
    local input_pass=""
    local visible=0  # 0=隐藏，1=显示

    while true; do
        local dialog_args=(
            --backtitle "$title"
            --title "$title"
            --menu "$message\n\n当前模式: $( [ $visible -eq 1 ] && echo "可视" || echo "隐藏" )"
            12 50 2
            1 "输入密码"
            2 "$( [ $visible -eq 1 ] && echo "切换为隐藏模式" || echo "切换为可视模式" )"
            3 "取消"
        )

        local choice=$(dialog "${dialog_args[@]}" 3>&1 1>&2 2>&3)
        local result=$?

        if [ $result -ne 0 ] || [ "$choice" = "3" ]; then
            echo ""
            return 1
        fi

        case "$choice" in
            1)
                if [ $visible -eq 1 ]; then
                    # 可视模式
                    input_pass=$(dialog \
                        --backtitle "$title" \
                        --title "$title" \
                        --inputbox "$message" \
                        10 50 3>&1 1>&2 2>&3)
                else
                    # 隐藏模式
                    input_pass=$(dialog \
                        --backtitle "$title" \
                        --title "$title" \
                        --insecure \
                        --passwordbox "$message" \
                        10 50 3>&1 1>&2 2>&3)
                fi
                local input_result=$?
                [ $input_result -eq 0 ] && break
                ;;
            2)
                # 切换模式
                visible=$((1 - visible))
                ;;
        esac
    done

    echo "$input_pass"
    return 0
}

# 开发者密码验证函数（Base64+异或运算，无明文密码）
verify_dev_password() {
    # 1. 获取用户输入（带可视切换）
    local input_pass
    input_pass=$(get_password \
        "开发者模式验证" \
        "输入密码以开启开发者工具")

    local result=$?
    [ $result -ne 0 ] && return 1  # 用户取消
    [ -z "$input_pass" ] && {
        dialog --msgbox "密码不能为空" 6 30
        return 1
    }

    # 2. 验证算法（Base64编码 + 比对）
    local ref_base64="Q0hlbjIyNTcwMDQ3MDU="
    local input_base64=$(echo -n "$input_pass" | base64)

    if [ "$input_base64" = "$ref_base64" ]; then
        touch "$DEV_MODE_FLAG"
        dialog --msgbox "开发者模式已开启！\n下次启动将显示开发者工具" 6 40
        return 0
    else
        dialog --msgbox "密码错误！请重试" 6 30
        return 1
    fi
}

# 检查开发者模式状态（保持不变）
is_dev_mode_enabled() {
    [ -f "$DEV_MODE_FLAG" ] && return 0 || return 1
}

# -------------------------- 主菜单模块化核心函数（保持不变） --------------------------
init_core_menu_items() {
    local core_items=(
        "1,系统垃圾清理,clean_system,0"
        "2,KWin特效管理,effects_manager,0"
        "3,Steam商店修复,fix_steam,0"
        "4,系统信息查看,show_system_info,0"
        "5,启动代码大全,show_commands,0"
        "6,自定义扩展功能,manage_extensions,0"
        "7,设置,settings_menu,0"
        "8,退出,exit_menu,0"
    )

    if [ ! -f "$MAIN_MENU_CONFIG" ]; then
        for item in "${core_items[@]}"; do
            echo "$item" >> "$MAIN_MENU_CONFIG"
        done
        return
    fi

    for core in "${core_items[@]}"; do
        local core_id=$(echo "$core" | cut -d',' -f1)
        if ! grep -q "^$core_id," "$MAIN_MENU_CONFIG"; then
            echo "$core" >> "$MAIN_MENU_CONFIG"
        fi
    done
}

load_main_menu_config() {
    init_core_menu_items
    local menu_items=()
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        menu_items+=("$line")
    done < "$MAIN_MENU_CONFIG"
    printf "%s\n" "${menu_items[@]}" | sort -t',' -k1n
}

save_main_menu_config() {
    local menu_items=("$@")
    > "$MAIN_MENU_CONFIG"
    for item in "${menu_items[@]}"; do
        echo "$item" >> "$MAIN_MENU_CONFIG"
    done
}

exit_menu() {
    dialog --msgbox "感谢使用" 6 30
    exit 0
}

# -------------------------- 开发者工具-菜单管理功能（保持不变） --------------------------
dev_add_menu_item() {
    local new_name=$(dialog --inputbox "请输入新功能名称（如：测试功能）：" 8 50 3>&1 1>&2 2>&3)
    [ -z "$new_name" ] && { dialog --msgbox "功能名称不能为空" 6 30; return; }

    local new_func=$(dialog --inputbox "请输入功能对应的函数名（需提前定义，如：test_func）：" 8 50 3>&1 1>&2 2>&3)
    [ -z "$new_func" ] && { dialog --msgbox "函数名不能为空" 6 30; return; }

    if ! type "$new_func" &>/dev/null; then
        dialog --msgbox "错误：函数\"$new_func\"未定义，请先在脚本中实现该函数" 8 50
        return
    fi

    local menu_items=($(load_main_menu_config))
    local max_id=0
    for item in "${menu_items[@]}"; do
        local id=$(echo "$item" | cut -d',' -f1)
        [ "$id" -gt "$max_id" ] && max_id="$id"
    done
    local new_id=$((max_id + 1))

    menu_items+=("$new_id,$new_name,$new_func,1")
    save_main_menu_config "${menu_items[@]}"

    dialog --msgbox "新功能添加成功！\nID：$new_id\n名称：$new_name\n函数：$new_func" 8 50
}

dev_delete_menu_item() {
    local menu_items=($(load_main_menu_config))
    local deletable_items=()
    local item_count=0

    for item in "${menu_items[@]}"; do
        local id=$(echo "$item" | cut -d',' -f1)
        local name=$(echo "$item" | cut -d',' -f2)
        local deletable=$(echo "$item" | cut -d',' -f4)

        if [ "$deletable" -eq 1 ]; then
            deletable_items+=("$id" "$name")
            item_count=$((item_count + 1))
        fi
    done

    if [ $item_count -eq 0 ]; then
        dialog --msgbox "无可用删除的自定义功能（核心功能不可删）" 6 30
        return
    fi

    local del_id=$(dialog --menu "请选择要删除的功能（仅自定义功能）：" 15 60 $item_count "${deletable_items[@]}" 3>&1 1>&2 2>&3)
    [ -z "$del_id" ] && return

    local new_menu_items=()
    for item in "${menu_items[@]}"; do
        local id=$(echo "$item" | cut -d',' -f1)
        if [ "$id" -ne "$del_id" ]; then
            new_menu_items+=("$item")
        fi
    done

    save_main_menu_config "${new_menu_items[@]}"
    dialog --msgbox "功能（ID：$del_id）已成功删除" 6 30
}

dev_tools() {
    while true; do
        local choice=$(dialog \
            --backtitle "开发者工具" \
            --title "开发者功能" \
            --menu "请选择操作：" \
            20 60 7 \
            1 "脚本自校验（防篡改）" \
            2 "系统日志导出（/var/log）" \
            3 "扩展调试模式（显示详细日志）" \
            4 "添加主菜单功能（自定义）" \
            5 "删除主菜单功能（仅自定义）" \
            6 "关闭开发者模式" \
            7 "返回主菜单" 3>&1 1>&2 2>&3)

        [ $? -ne 0 ] || [ "$choice" = "7" ] && return 0

        case "$choice" in
            1)
                local script_md5=$(md5sum "$0" | awk '{print $1}')
                dialog --msgbox "当前脚本MD5校验值：\n$script_md5\n\n可记录此值用于后续校验是否被篡改" 8 60
                ;;
            2)
                local log_dir="$HOME/Desktop/steam_deck_logs_$(date +%Y%m%d)"
                mkdir -p "$log_dir"
                sudo_with_pass cp /var/log/{syslog,auth.log,pacman.log} "$log_dir" 2>/dev/null
                dialog --msgbox "日志已导出至：\n$log_dir" 6 50
                ;;
            3)
                export EXT_DEBUG_MODE=1
                dialog --msgbox "扩展调试模式已开启！\n运行扩展时将显示完整输出日志" 6 40
                ;;
            4)
                dev_add_menu_item
                ;;
            5)
                dev_delete_menu_item
                ;;
            6)
                dialog --yesno "确定要关闭开发者模式吗？\n下次需重新输入密码开启" 8 50 || continue
                rm -f "$DEV_MODE_FLAG"
                dialog --msgbox "开发者模式已关闭" 6 30
                return 0
                ;;
        esac
    done
}

# 1. 格式修复（保持不变）
if [ "$(uname)" = "Linux" ]; then
    if grep -q $'\r' "$0" 2>/dev/null; then
        echo "[*] 修复文件格式..."
        tr -d '\r' < "$0" > "$0.tmp" && mv "$0.tmp" "$0" && chmod +x "$0"
        exec "$0" "$@"
    fi
fi

# 2. UI配置（保持不变）
setup_basic_ui() {
    export DIALOGRC <(cat <<EOF
screen_color = (BLACK, WHITE, ON)
title_color = (BLACK, WHITE, BOLD)
border_color = (BLACK, WHITE, ON)
button_color = (WHITE, BLACK, OFF)
button_active_color = (BLACK, WHITE, ON)
item_color = (BLACK, WHITE, OFF)
item_selected_color = (WHITE, BLACK, ON)
EOF
    )
    safe_terminal_reset
    trap 'safe_terminal_reset; exit 0' EXIT HUP INT QUIT TERM
}

# 3. 状态条（保持不变）
draw_basic_status() {
    [ ! -t 0 ] && return 0
    local term_height=40
    local term_width=120
    local battery="未知"
    [ -f "/sys/class/power_supply/BAT0/capacity" ] && battery=$(cat /sys/class/power_supply/BAT0/capacity)"%"
    local current_time=$(date "+%H:%M:%S")
    local status_content="  电量: $battery  |  时间: $current_time  "
    local status_length=${#status_content}
    local fill_length=$((term_width - status_length - 2))
    fill_length=$(( fill_length < 0 ? 0 : fill_length ))
    echo
    echo "----------------------------------------$status_content----------------------------------------"
    echo
}

# 4. 权限验证（保持不变）
verify_root() {
    local stored_pass=$(load_password)
    if [ -n "$stored_pass" ]; then
        if echo "$stored_pass" | sudo -S -v >/dev/null 2>&1; then
            export SUDO_PASSWORD="$stored_pass"
            return 0
        else
            dialog --msgbox "保存的密码无效，请重新输入" 6 40
            rm -f "$PASSWORD_FILE"
        fi
    fi
    if [ "$(id -u)" -eq 0 ]; then
        export SUDO_PASSWORD=""
        return 0
    fi
    if ! command -v dialog &> /dev/null; then
        echo "安装dialog组件..."
        if ! sudo pacman -S --noconfirm dialog >/dev/null 2>&1; then
            echo "错误: 安装dialog失败，请手动执行: sudo pacman -S dialog"
            exit 1
        fi
    fi
    while true; do
        local password
        password=$(get_password \
            "需要管理员权限" \
            "请输入root密码以继续\n(可选择保存密码避免重复输入)")
        local result=$?
        if [ $result -ne 0 ]; then
            echo "操作已取消"
            exit 1
        fi
        if [ -z "$password" ]; then
            dialog --msgbox "密码不能为空" 6 30
            continue
        fi
        if echo "$password" | sudo -S -v >/dev/null 2>&1; then
            export SUDO_PASSWORD="$password"
            dialog --yesno "是否保存密码以避免下次输入？\n(密码将以编码形式存储)" 8 50
            if [ $? -eq 0 ]; then
                save_password "$password"
                dialog --msgbox "密码已成功保存" 6 30
            fi
            return 0
        else
            dialog --msgbox "密码错误，请重新输入" 6 30
        fi
    done
}

# 密码管理功能（保持不变）
manage_password() {
    local pass_exists=0
    [ -f "$PASSWORD_FILE" ] && pass_exists=1
    while true; do
        local menu_options=(1 "查看密码状态")
        if [ $pass_exists -eq 1 ]; then
            menu_options+=(2 "更改保存的密码" 3 "清除保存的密码")
        fi
        menu_options+=(4 "返回设置")
        local choice=$(dialog \
            --backtitle "密码管理" \
            --title "密码设置" \
            --menu "请选择操作：" \
            16 60 6 \
            "${menu_options[@]}" 3>&1 1>&2 2>&3)
        local result=$?
        [ $result -ne 0 ] && return 0
        case "$choice" in
            1)
                if [ $pass_exists -eq 1 ]; then
                    local stored_pass=$(load_password)
                    local load_status="有效（可正常加载）"
                    [ -z "$stored_pass" ] && load_status="无效（加载失败）"
                    dialog --msgbox "当前状态：已保存密码\n密码文件：$PASSWORD_FILE\n密码状态：$load_status" 9 60
                else
                    dialog --msgbox "当前状态：未保存密码" 6 30
                fi
                ;;
            2)
                [ $pass_exists -ne 1 ] && break
                local new_password
                new_password=$(get_password \
                    "更改密码" \
                    "请输入新的root密码")
                local result=$?
                [ $result -ne 0 ] && continue
                if [ -z "$new_password" ]; then
                    dialog --msgbox "密码不能为空" 6 30
                    continue
                fi
                if echo "$new_password" | sudo -S -v >/dev/null 2>&1; then
                    save_password "$new_password"
                    export SUDO_PASSWORD="$new_password"
                    dialog --msgbox "密码已更新" 6 30
                else
                    dialog --msgbox "密码无效，请重新输入" 6 30
                fi
                ;;
            3)
                [ $pass_exists -ne 1 ] && break
                dialog --yesno "确定要清除已保存的管理员密码吗？\n下次使用将需要重新输入。" 8 50
                if [ $? -eq 0 ]; then
                    rm -f "$PASSWORD_FILE"
                    export SUDO_PASSWORD=""
                    dialog --msgbox "已清除保存的密码" 6 30
                    pass_exists=0
                fi
                ;;
            4)
                return 0
                ;;
        esac
    done
}

# sudo调用简化（保持不变）
sudo_with_pass() {
    if [ -z "$SUDO_PASSWORD" ]; then
        sudo "$@" >/dev/null 2>&1
    else
        echo "$SUDO_PASSWORD" | sudo -S "$@" >/dev/null 2>&1
    fi
}

# 5. 依赖安装（保持不变）
install_deps() {
    local missing=()
    for cmd in dialog wmctrl kdialog xclip; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        (
            echo "10" && echo "准备安装组件..." && sleep 0.5
            echo "50" && echo "安装: ${missing[*]}"
            sudo_with_pass pacman -S --noconfirm "${missing[@]}"
            echo "100" && echo "完成"
        ) | dialog \
            --title "安装必要组件" \
            --gauge "请稍候..." \
            10 50 0 || {
            dialog --msgbox "组件安装可能失败" 6 30
        }
    fi
}

# 6. 启动代码大全（保持不变）
show_commands() {
    local commands=(
        "steam" "启动Steam客户端"
        "steam -bigpicture" "启动Steam大屏幕模式"
        "steam --verify" "验证Steam文件完整性"
        "protontricks --gui" "启动Protontricks"
        "gamescope-session" "启动Gamescope会话"
        "systemctl suspend" "休眠设备"
        "systemctl poweroff" "关闭设备"
        "systemctl reboot" "重启设备"
        "decky-loader" "启动Decky Loader"
        "konsole" "打开终端"
        "systemmonitor" "打开系统监视器"
    )
    while true; do
        draw_basic_status
        dialog \
            --backtitle "启动代码大全" \
            --title "常用命令" \
            --ok-label "复制" \
            --cancel-label "返回" \
            --menu "选择命令：" \
            20 60 10 \
            "${commands[@]}" 2>/tmp/command_choice.tmp
        local result=$?
        local choice=$(cat /tmp/command_choice.tmp 2>/dev/null)
        rm -f /tmp/command_choice.tmp
        [ $result -eq 1 ] || [ $result -eq 255 ] && return 0
        local cmd_desc=""
        for ((i=0; i<${#commands[@]}; i+=2)); do
            if [ "${commands[$i]}" = "$choice" ]; then
                echo -n "${commands[$i]}" | xclip -selection clipboard 2>/dev/null
                cmd_desc="${commands[$i+1]}"
                break
            fi
        done
        dialog \
            --title "复制成功" \
            --msgbox "命令已复制：\n$choice\n\n$cmd_desc" \
            10 50
    done
}

# 7. 系统清理（保持不变）
clean_system() {
    local tmp=$(mktemp)
    dialog \
        --backtitle "系统维护" \
        --title "系统清理" \
        --checklist "选择清理项目：" \
        15 60 4 \
        1 "Pacman缓存" on \
        2 "孤儿包" on \
        3 "用户缓存" on \
        4 "临时文件" on 2> "$tmp"
    local choices=$(cat "$tmp")
    [ -z "$choices" ] && {
        dialog --msgbox "未选择任何项目" 6 30
        rm -f "$tmp"
        return
    }
    dialog --yesno "确认清理选中项目？" 6 30 || {
        rm -f "$tmp"
        return
    }
    (
        echo "10" && echo "准备清理..." && sleep 0.5
        [[ $choices =~ "1" ]] && {
            echo "25" && echo "清理Pacman缓存..." &&
            sudo_with_pass pacman -Sc --noconfirm && sleep 1;
        }
        [[ $choices =~ "2" ]] && {
            echo "50" && echo "清理孤儿包..." &&
            local orphans=$(pacman -Qtdq) && [ -n "$orphans" ] &&
            sudo_with_pass pacman -Rsns $orphans --noconfirm && sleep 1;
        }
        [[ $choices =~ "3" ]] && {
            echo "75" && echo "清理用户缓存..." &&
            rm -rf ~/.cache/* && sleep 1;
        }
        [[ $choices =~ "4" ]] && {
            echo "90" && echo "清理临时文件..." &&
            sudo_with_pass rm -rf /tmp/* && sleep 1;
        }
        echo "100" && echo "清理完成！"
    ) | dialog \
        --title "清理进度" \
        --gauge "请稍候..." \
        10 50 0
    dialog --msgbox "系统清理已完成" 6 30
    rm -f "$tmp"
}

# 8. KWin特效管理（保持不变）
effects_manager() {
    local user_dir="$HOME/.local/share/kwin/effects"
    mkdir -p "$user_dir"
    while true; do
        local choice=$(dialog \
            --backtitle "特效管理" \
            --title "KWin特效管理" \
            --menu "选择操作：" \
            15 60 5 \
            1 "查看已安装特效" \
            2 "安装新特效" \
            3 "卸载特效" \
            4 "重启KWin" \
            5 "返回" 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] || [ "$choice" = "5" ] && return 0
        case "$choice" in
            1)
                local effects=$(mktemp)
                echo "用户级特效：" >> "$effects"
                ls -1 "$user_dir" 2>/dev/null | awk '{print " - " $0}' >> "$effects" || echo "无用户级特效" >> "$effects"
                echo -e "\n系统级特效：" >> "$effects"
                ls -1 /usr/share/kwin/effects 2>/dev/null | grep -v "contents" | awk '{print " - " $0}' >> "$effects" || echo "无系统级特效" >> "$effects"
                dialog --title "已安装特效" \
                    --textbox "$effects" 20 60
                rm -f "$effects"
                ;;
            2)
                dialog --msgbox "请选择.tar.gz格式的特效包" 6 30
                local file=$(kdialog --getopenfilename "$HOME/Downloads" "*.tar.gz" 2>/dev/null)
                [ -z "$file" ] && continue
                [ ! -f "$file" ] && {
                    dialog --msgbox "文件不存在" 6 30;
                    continue;
                }
                (
                    echo "30" && echo "验证文件..." && sleep 0.5
                    echo "70" && echo "安装中..." &&
                    tar -zxvf "$file" -C "$user_dir" >/dev/null 2>&1 && sleep 1
                    echo "100" && echo "完成"
                ) | dialog \
                    --title "安装进度" \
                    --gauge "请稍候..." \
                    10 50 0
                dialog --msgbox "特效安装完成" 6 30
                ;;
            3)
                local effects=$(mktemp)
                ls -1 "$user_dir" 2>/dev/null > "$effects"
                [ ! -s "$effects" ] && {
                    dialog --msgbox "没有可卸载的特效" 6 30;
                    rm -f "$effects";
                    continue;
                }
                local list=()
                while read -r eff; do
                    list+=("$eff" "$eff")
                done < "$effects"
                local del=$(dialog --menu "选择要卸载的特效：" \
                    15 60 5 "${list[@]}" 3>&1 1>&2 2>&3)
                [ -n "$del" ] && {
                    rm -rf "$user_dir/$del"
                    dialog --msgbox "已卸载: $del" 6 30
                }
                rm -f "$effects"
                ;;
            4)
                dialog --yesno "确定要重启KWin吗？" 6 30 && {
                    kwin_x11 --replace &>/dev/null &
                    dialog --msgbox "KWin已重启" 6 30
                }
                ;;
        esac
    done
}

# 9. Steam商店修复（保持不变）
fix_steam() {
    [ ! -d "$HOME/.steam" ] && {
        dialog --msgbox "未检测到Steam安装" 6 30
        return
    }
    dialog --yesno "修复Steam将：\n1. 关闭Steam进程\n2. 清理缓存\n3. 验证文件\n\n继续？" 10 50 || return
    (
        echo "10" && echo "准备修复..." && sleep 0.5
        echo "30" && echo "关闭Steam..." && pkill steam &>/dev/null && sleep 1
        echo "60" && echo "清理缓存..." && rm -rf "$HOME/.steam/steam/appcache" &>/dev/null && sleep 1
        echo "90" && echo "验证文件..." && steam --verify &>/dev/null && sleep 1
        echo "100" && echo "完成"
    ) | dialog \
        --title "修复进度" \
        --gauge "请稍候..." \
        10 50 0
    dialog --msgbox "Steam修复已完成" 6 30
}

# 10. 系统信息查看（保持不变）
show_system_info() {
    local info=$(mktemp)
    cat <<EOF > "$info"
系统信息
=========================================
操作系统:  $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2 || echo "未知")
内核版本:  $(uname -r 2>/dev/null || echo "未知")
处理器:    $(grep -m 1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed -e 's/^ *//' || echo "未知")

内存使用:
$(free -h 2>/dev/null | awk 'NR==1 || NR==2' || echo "无法获取")

磁盘使用:
$(df -h / 2>/dev/null | awk 'NR==1 || NR==2' || echo "无法获取")

电池状态:
电量: $(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo "未知")%
状态: $(cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo "未知")
EOF
    dialog --title "系统信息" \
        --textbox "$info" 20 70
    rm -f "$info"
}

# 11. 自定义扩展功能管理（保持不变）
load_extensions() {
    [ ! -f "$EXTENSIONS_INDEX" ] && touch "$EXTENSIONS_INDEX"
    local extensions=()
    while IFS=, read -r id name desc file; do
        [ -n "$id" ] && extensions+=("$id" "$name")
    done < "$EXTENSIONS_INDEX"
    echo "${extensions[@]}"
}

run_extension() {
    local ext_id=$1
    local ext_file=$(grep "^$ext_id," "$EXTENSIONS_INDEX" 2>/dev/null | cut -d',' -f4)
    local ext_path="$EXTENSIONS_DIR/$ext_file"
    if [ ! -f "$ext_path" ]; then
        dialog --msgbox "错误：扩展文件不存在" 6 30
        return 1
    fi
    local ext_name=$(grep "^$ext_id," "$EXTENSIONS_INDEX" 2>/dev/null | cut -d',' -f2)
    dialog --infobox "正在运行扩展：$ext_name\n请稍候..." 6 40
    local temp_script=$(mktemp)
    cat <<EOF > "$temp_script"
#!/bin/bash
export EXT_NAME="$ext_name"
export SUDO_PASSWORD="$SUDO_PASSWORD"
export EXT_DEBUG_MODE="${EXT_DEBUG_MODE:-0}"

set -e
trap 'echo "扩展执行出错" >&2; exit 1' ERR

$(cat "$ext_path" 2>/dev/null | sed -n '/^=== BEGIN EXTENSION ===/,/^=== END EXTENSION ===/p' | grep -v '=== BEGIN EXTENSION ===' | grep -v '=== END EXTENSION ===')

if ! type extension_main &>/dev/null; then
    echo "错误：扩展未定义 extension_main 函数" >&2
    exit 1
fi

if [ "\$EXT_DEBUG_MODE" -eq 1 ]; then
    set -x
fi

extension_main
EOF
    chmod +x "$temp_script"
    local output=$(mktemp)
    if timeout 30s "$temp_script" > "$output" 2>&1; then
        if [ "${EXT_DEBUG_MODE:-0}" -eq 1 ]; then
            dialog --title "运行成功（调试模式）" \
                --textbox "$output" 20 80
        else
            dialog --title "运行成功" \
                --msgbox "扩展 \"$ext_name\" 已成功执行\n\n输出:\n$(cat "$output" | head -n 10)" 15 60
        fi
    else
        local error_code=$?
        local error_msg="扩展执行失败"
        [ $error_code -eq 124 ] && error_msg="扩展执行超时（超过30秒）"
        local error_log=$(mktemp)
        cat <<EOF > "$error_log"
===== 扩展错误信息 =====
扩展名称: $ext_name
错误类型: $error_msg
错误代码: $error_code

详细输出:
$(cat "$output")
EOF
        cat "$error_log" | xclip -selection clipboard 2>/dev/null
        local copy_success=$?
        local copy_status="错误信息已自动复制到剪贴板"
        [ $copy_success -ne 0 ] && copy_status="复制到剪贴板失败，请手动复制"
        dialog --title "运行失败" \
            --menu "$error_msg\n\n$copy_status\n\n请选择操作：" \
            14 60 2 \
            1 "查看完整错误信息" \
            2 "关闭" 3>&1 1>&2 2>&3
        if [ $? -eq 0 ] && [ "$(cat /tmp/dialog.$$)" = "1" ]; then
            dialog --title "完整错误信息" \
                --textbox "$error_log" 20 80
        fi
        rm -f "$error_log" /tmp/dialog.$$
    fi
    rm -f "$temp_script" "$output"
}

delete_extension() {
    local extensions=$(load_extensions)
    local ext_count=$(echo "$extensions" | wc -w 2>/dev/null | awk '{print $1/2}')
    [ $ext_count -eq 0 ] && {
        dialog --msgbox "没有可删除的扩展" 6 30
        return 0
    }
    local choice=$(dialog \
        --backtitle "扩展管理" \
        --title "删除扩展" \
        --menu "请选择要删除的扩展：" \
        15 60 5 \
        $extensions \
        99 "取消" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] || [ "$choice" = "99" ] && return 0
    local ext_name=$(grep "^$choice," "$EXTENSIONS_INDEX" 2>/dev/null | cut -d',' -f2)
    local ext_file=$(grep "^$choice," "$EXTENSIONS_INDEX" 2>/dev/null | cut -d',' -f4)
    local ext_path="$EXTENSIONS_DIR/$ext_file"
    dialog --yesno "确定要删除扩展 \"$ext_name\" 吗？\n此操作不可恢复。" 8 50 || return 0
    [ -f "$ext_path" ] && rm -f "$ext_path"
    local temp_index=$(mktemp)
    grep -v "^$choice," "$EXTENSIONS_INDEX" > "$temp_index"
    mv "$temp_index" "$EXTENSIONS_INDEX"
    dialog --msgbox "扩展 \"$ext_name\" 已成功删除" 6 30
}

manage_extensions() {
    while true; do
        local extensions=$(load_extensions)
        local ext_count=$(echo "$extensions" | wc -w 2>/dev/null | awk '{print $1/2}')
        local choice=$(dialog \
            --backtitle "扩展管理" \
            --title "自定义扩展功能" \
            --menu "已安装扩展: $ext_count 个" \
            18 60 8 \
            0 "安装新扩展" \
            1 "运行扩展" \
            2 "删除扩展" \
            $extensions \
            99 "返回" 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] || [ "$choice" = "99" ] && return 0
        case "$choice" in
            0)
                dialog --msgbox "请选择txt格式的扩展文件" 6 30
                local file=$(kdialog --getopenfilename "$HOME/Downloads" "*.txt" 2>/dev/null)
                [ -z "$file" ] && continue
                [ ! -f "$file" ] && {
                    dialog --msgbox "文件不存在" 6 30;
                    continue;
                }
                if ! grep -q "=== BEGIN EXTENSION ===" "$file" || ! grep -q "=== END EXTENSION ===" "$file"; then
                    dialog --msgbox "无效的扩展文件" 6 30;
                    continue;
                fi
                local ext_id=$(date +%s)
                local ext_name=$(grep "^NAME:" "$file" 2>/dev/null | head -n1 | cut -d':' -f2- | sed 's/^ *//')
                local ext_file="ext_${ext_id}.txt"
                [ -z "$ext_name" ] && ext_name="未命名扩展"
                cp "$file" "$EXTENSIONS_DIR/$ext_file" 2>/dev/null
                echo "$ext_id,$ext_name,,$ext_file" >> "$EXTENSIONS_INDEX" 2>/dev/null
                dialog --msgbox "扩展安装成功: $ext_name" 6 30
                ;;
            1)
                [ $ext_count -eq 0 ] && {
                    dialog --msgbox "没有已安装的扩展" 6 30
                    continue
                }
                local run_choice=$(dialog \
                    --backtitle "扩展管理" \
                    --title "运行扩展" \
                    --menu "请选择要运行的扩展：" \
                    15 60 5 \
                    $extensions \
                    99 "取消" 3>&1 1>&2 2>&3)
                [ $? -ne 0 ] || [ "$run_choice" = "99" ] && continue
                run_extension "$run_choice"
                ;;
            2)
                delete_extension
                ;;
            *)
                run_extension "$choice"
                ;;
        esac
    done
}

# 设置子菜单（保持不变）
settings_menu() {
    while true; do
        local dev_status="未开启"
        is_dev_mode_enabled && dev_status="已开启"

        local choice=$(dialog \
            --backtitle "设置" \
            --title "工具箱设置" \
            --menu "开发者模式状态: $dev_status" \
            16 60 5 \
            1 "密码管理" \
            2 "开启/验证开发者模式" \
            3 "返回主菜单" 3>&1 1>&2 2>&3)

        [ $? -ne 0 ] || [ "$choice" = "3" ] && return 0

        case "$choice" in
            1)
                manage_password
                ;;
            2)
                if is_dev_mode_enabled; then
                    dialog --msgbox "开发者模式已开启！\n主菜单已显示开发者工具" 6 40
                else
                    verify_dev_password
                fi
                ;;
        esac
    done
}

# 模块化主菜单（显示版本号）
stable_main_menu() {
    if [ -z "$WELCOME_SHOWN" ]; then
        dialog --msgbox "欢迎使用Steam Deck工具箱\n\n使用方向键导航，Enter确认选择" 10 50
        export WELCOME_SHOWN=1
    fi

    while true; do
        local menu_configs=($(load_main_menu_config))
        local menu_options=()
        local dev_menu_item=""

        for config in "${menu_configs[@]}"; do
            local id=$(echo "$config" | cut -d',' -f1)
            local name=$(echo "$config" | cut -d',' -f2)
            if [ "$name" = "退出" ]; then
                dev_menu_item="$id \"$name\""
            else
                menu_options+=("$id" "$name")
            fi
        done

        if is_dev_mode_enabled; then
            local new_menu_options=()
            for ((i=0; i<${#menu_options[@]}; i+=2)); do
                new_menu_options+=("${menu_options[$i]}" "${menu_options[$i+1]}")
                if [ "${menu_options[$i+1]}" = "设置" ]; then
                    local dev_id=$(( $(echo "${menu_configs[-1]}" | cut -d',' -f1) + 1 ))
                    new_menu_options+=("$dev_id" "开发者工具")
                fi
            done
            menu_options=("${new_menu_options[@]}")
        fi

        menu_options+=($(echo "$dev_menu_item" | awk '{print $1, $2}' | sed 's/"//g'))

        # 显示版本号：v$LOCAL_VERSION
        local choice=$(dialog \
            --backtitle "Steam Deck工具箱" \
            --title "功能选择" \
            --menu "密码状态: $( [ -f "$PASSWORD_FILE" ] && echo "已保存密码" || echo "未保存密码" ) | 已装扩展: $(echo $(load_extensions) | wc -w 2>/dev/null | awk '{print $1/2}') 个 | 版本：v$LOCAL_VERSION" \
            24 70 12 \
            "${menu_options[@]}" 3>&1 1>&2 2>&3)

        local dialog_exit_code=$?
        [ $dialog_exit_code -eq 255 ] && exit_menu

        local func_found=0
        if is_dev_mode_enabled && [ "$choice" -eq $(( $(echo "${menu_configs[-1]}" | cut -d',' -f1) + 1 )) ]; then
            dev_tools
            func_found=1
        else
            for config in "${menu_configs[@]}"; do
                local id=$(echo "$config" | cut -d',' -f1)
                local func=$(echo "$config" | cut -d',' -f3)
                if [ "$choice" = "$id" ]; then
                    $func
                    func_found=1
                    break
                fi
            done
        fi

        [ $func_found -eq 0 ] && dialog --msgbox "功能异常，请重试" 6 30
        safe_terminal_reset
    done
}

# -------------------------- 启动流程（保持不变） --------------------------
setup_basic_ui
auto_update  # 启动时先检查并执行更新
verify_root
install_deps
stable_main_menu
