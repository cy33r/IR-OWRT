#!/bin/sh

# ==============================================================================
#  VIP3R OPENWRT MASTER SCRIPT - FIXED & STABLE (SMART RAM EDITION + UNLOCKER)
# ==============================================================================

# --- COLORS ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- GLOBAL VARS ---
BIN_DIR="/usr/bin"
TEMP_DIR="/tmp/vip3r_update"
GEO_DIR="/usr/share/v2ray"

# ==============================================================================
#  1. SYSTEM CHECKS & INFO
# ==============================================================================

check_internet_connection() {
    echo -e "${YELLOW}>>> CHECKING INTERNET CONNECTIVITY...${NC}"
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        echo -e "${GREEN}>>> INTERNET CONNECTION: OK${NC}"
    else
        echo -e "${RED}>>> ERROR: NO INTERNET CONNECTION DETECTED!${NC}"
        echo -e "${RED}>>> PLEASE FIX YOUR NETWORK BEFORE PROCEEDING.${NC}"
        echo "PRESS ENTER TO EXIT..."
        read DUMMY
        exit 1
    fi
}

get_sys_info() {
    # MODEL
    MODEL=$(cat /tmp/sysinfo/model 2>/dev/null || echo "UNKNOWN DEVICE")
    MODEL=$(echo "$MODEL" | tr 'a-z' 'A-Z')

    # ARCHITECTURE
    ARCH=$(opkg print-architecture | awk '{print $2}' | grep -v "all" | grep -v "noarch" | tail -n 1)
    [ -z "$ARCH" ] && ARCH="UNKNOWN"

    # CPU DETAILS
    CPU_MODEL=$(grep -m 1 "model name" /proc/cpuinfo | cut -d: -f2 | sed 's/^[ \t]*//')
    [ -z "$CPU_MODEL" ] && CPU_MODEL=$(grep -m 1 "system type" /proc/cpuinfo | cut -d: -f2 | sed 's/^[ \t]*//')
    CPU_MODEL=$(echo "$CPU_MODEL" | tr 'a-z' 'A-Z')

    # MEMORY
    TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    FREE_RAM_KB=$(grep MemFree /proc/meminfo | awk '{print $2}')
    BUFFERS_KB=$(grep Buffers /proc/meminfo | awk '{print $2}')
    CACHED_KB=$(grep ^Cached /proc/meminfo | awk '{print $2}')
    
    USED_RAM_KB=$((TOTAL_RAM_KB - FREE_RAM_KB - BUFFERS_KB - CACHED_KB))
    
    TOTAL_RAM=$((TOTAL_RAM_KB / 1024))
    USED_RAM=$((USED_RAM_KB / 1024))
    FREE_RAM=$((FREE_RAM_KB / 1024))

    # STORAGE (OVERLAY)
    if df -h /overlay >/dev/null 2>&1; then
        TARGET_DISK="/overlay"
    else
        TARGET_DISK="/"
    fi
    
    DISK_TOTAL=$(df -h $TARGET_DISK | awk 'NR==2 {print $2}')
    DISK_USED=$(df -h $TARGET_DISK | awk 'NR==2 {print $3}')
    DISK_FREE=$(df -h $TARGET_DISK | awk 'NR==2 {print $4}')

    # TEMP STORAGE (RAM DISK)
    TEMP_TOTAL=$(df -h /tmp | awk 'NR==2 {print $2}')
    TEMP_FREE=$(df -h /tmp | awk 'NR==2 {print $4}')

    # DNS CHECK
    DNS_INFO=$(grep "nameserver" /tmp/resolv.conf.d/resolv.conf.auto 2>/dev/null | awk '{print $2}' | xargs)
    [ -z "$DNS_INFO" ] && DNS_INFO=$(grep "nameserver" /etc/resolv.conf 2>/dev/null | awk '{print $2}' | xargs)
    [ -z "$DNS_INFO" ] && DNS_INFO="UNKNOWN/LOCAL"
}

# ==============================================================================
#  2. ARCHITECTURE MAPPING
# ==============================================================================

get_core_arch() {
    XRAY_ARCH="UNKNOWN"
    SING_ARCH="UNKNOWN"
    HYS_ARCH="UNKNOWN"

    case "$ARCH" in
        "x86_64")
            XRAY_ARCH="64"
            SING_ARCH="amd64"
            HYS_ARCH="amd64"
            ;;
        "aarch64_generic"|"aarch64_cortex-a53"|"aarch64"|"aarch64_cortex-a72")
            XRAY_ARCH="arm64-v8a"
            SING_ARCH="arm64"
            HYS_ARCH="arm64"
            ;;
        "arm_cortex-a7_neon-vfpv4"|"arm_cortex-a9")
            XRAY_ARCH="arm32-v7a"
            SING_ARCH="armv7"
            HYS_ARCH="arm"
            ;;
        "mips_24kc"|"mips_mips32")
            XRAY_ARCH="mips32le"
            SING_ARCH="mips32le"
            HYS_ARCH="mipsle"
            ;;
        "mipsel_24kc"|"mipsel_74kc")
            XRAY_ARCH="mips32le"
            SING_ARCH="mips32le"
            HYS_ARCH="mipsle"
            ;;
        *)
            if echo "$ARCH" | grep -q "aarch64"; then
                XRAY_ARCH="arm64-v8a"
                SING_ARCH="arm64"
                HYS_ARCH="arm64"
            elif echo "$ARCH" | grep -q "x86"; then
                XRAY_ARCH="64"
                SING_ARCH="amd64"
                HYS_ARCH="amd64"
            fi
            ;;
    esac
}

# ==============================================================================
#  3. HELPER FUNCTIONS
# ==============================================================================

prepare_environment() {
    mkdir -p "$TEMP_DIR"
    rm -rf "$TEMP_DIR/*"
    echo -e "${YELLOW}>>> TEMP ENVIRONMENT PREPARED IN $TEMP_DIR (RAM)${NC}"
}

force_unlock_fs() {
    # NEW FUNCTION: FIXES 'READ-ONLY FILE SYSTEM' ERROR
    echo -e "${YELLOW}>>> CHECKING FILESYSTEM LOCKS...${NC}"
    mount -o remount,rw /overlay >/dev/null 2>&1
    mount -o remount,rw / >/dev/null 2>&1
    echo -e "${GREEN}>>> FILESYSTEM REMOUNTED AS READ-WRITE.${NC}"
}

emergency_cleaner() {
    # NEW FUNCTION: DELETES USELESS FILES IF DISK IS 0KB TO ALLOW OPERATIONS
    echo -e "${YELLOW}>>> EMERGENCY CLEAN: REMOVING OLD LISTS & BACKUPS...${NC}"
    rm -rf /var/opkg-lists/* >/dev/null 2>&1
    # Remove old binary backups to free space
    rm -f "$BIN_DIR/xray.bak" >/dev/null 2>&1
    rm -f "$BIN_DIR/sing-box.bak" >/dev/null 2>&1
    rm -f "$BIN_DIR/hysteria.bak" >/dev/null 2>&1
}

stop_passwall() {
    echo -e "${BLUE}>>> STOPPING PASSWALL SERVICES...${NC}"
    /etc/init.d/passwall2 stop >/dev/null 2>&1
    /etc/init.d/passwall stop >/dev/null 2>&1
}

restart_passwall() {
    echo -e "${BLUE}>>> RESTARTING PASSWALL SERVICES...${NC}"
    /etc/init.d/passwall2 restart >/dev/null 2>&1
    /etc/init.d/passwall restart >/dev/null 2>&1
    echo -e "${GREEN}>>> SERVICE RESTARTED.${NC}"
}

backup_binary() {
    local NAME=$1
    if [ -f "$BIN_DIR/$NAME" ]; then
        echo -e "${YELLOW}>>> BACKING UP CURRENT $NAME...${NC}"
        # Only backup if we have space, otherwise skip to prevent "No space left"
        if df /overlay | awk 'NR==2 { if ($4 > 200) exit 0; else exit 1; }'; then
             cp "$BIN_DIR/$NAME" "$BIN_DIR/${NAME}.bak"
        else
             echo -e "${RED}>>> WARNING: LOW DISK SPACE. SKIPPING BACKUP.${NC}"
        fi
    fi
}

pause_script() {
    echo ""
    echo -e "PRESS ${YELLOW}ENTER${NC} TO CONTINUE..."
    read DUMMY
}

# ==============================================================================
#  4. UPDATE FUNCTIONS
# ==============================================================================

update_xray() {
    prepare_environment
    echo -e "${YELLOW}>>> STARTING XRAY UPDATE CHECK...${NC}"
    echo -e "${BLUE}>>> ARCH: $XRAY_ARCH${NC}"
    
    DOWNLOAD_URL=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases/latest" | grep "browser_download_url" | grep -i "linux-$XRAY_ARCH.zip" | cut -d '"' -f 4 | head -n 1)
    
    if [ -z "$DOWNLOAD_URL" ]; then
        echo -e "${RED}>>> ERROR: COULD NOT FIND XRAY DOWNLOAD LINK.${NC}"
        pause_script
        return
    fi
    
    echo -e "${BLUE}>>> DOWNLOADING: $DOWNLOAD_URL${NC}"
    echo -e "${BLUE}>>> SAVING TO TEMP SPACE (RAM)...${NC}"
    curl -L -o "$TEMP_DIR/xray.zip" "$DOWNLOAD_URL"
    
    if [ ! -s "$TEMP_DIR/xray.zip" ]; then
        echo -e "${RED}>>> ERROR: DOWNLOAD FAILED OR SPACE FULL IN RAM.${NC}"
        pause_script
        return
    fi
    
    stop_passwall
    force_unlock_fs
    emergency_cleaner
    # backup_binary "xray" # Skipped to save space on 0kb devices
    
    echo -e "${BLUE}>>> EXTRACTING IN RAM...${NC}"
    unzip -o "$TEMP_DIR/xray.zip" -d "$TEMP_DIR/extract" >/dev/null 2>&1
    
    if [ -f "$TEMP_DIR/extract/xray" ]; then
        echo -e "${BLUE}>>> INSTALLING TO $BIN_DIR...${NC}"
        # SMART FIX: REMOVE OLD FILE FIRST TO FREE DISK SPACE (FORCE)
        rm -rf "$BIN_DIR/xray" >/dev/null 2>&1
        cp -f "$TEMP_DIR/extract/xray" "$BIN_DIR/xray"
        chmod +x "$BIN_DIR/xray"
        echo -e "${GREEN}>>> XRAY CORE UPDATED SUCCESSFULLY!${NC}"
    else
        echo -e "${RED}>>> ERROR: BINARY NOT FOUND IN ZIP.${NC}"
    fi
    
    restart_passwall
    pause_script
}

update_singbox() {
    prepare_environment
    echo -e "${YELLOW}>>> STARTING SING-BOX UPDATE CHECK...${NC}"
    echo -e "${BLUE}>>> ARCH: $SING_ARCH${NC}"
    
    DOWNLOAD_URL=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | grep "browser_download_url" | grep -i "linux-$SING_ARCH.tar.gz" | cut -d '"' -f 4 | head -n 1)
    
    if [ -z "$DOWNLOAD_URL" ]; then
        echo -e "${RED}>>> ERROR: COULD NOT FIND SING-BOX DOWNLOAD LINK.${NC}"
        pause_script
        return
    fi
    
    echo -e "${BLUE}>>> DOWNLOADING: $DOWNLOAD_URL${NC}"
    echo -e "${BLUE}>>> SAVING TO TEMP SPACE (RAM)...${NC}"
    curl -L -o "$TEMP_DIR/singbox.tar.gz" "$DOWNLOAD_URL"
    
    if [ ! -s "$TEMP_DIR/singbox.tar.gz" ]; then
        echo -e "${RED}>>> ERROR: DOWNLOAD FAILED OR SPACE FULL IN RAM.${NC}"
        return
    fi
    
    stop_passwall
    force_unlock_fs
    emergency_cleaner
    # backup_binary "sing-box"
    
    echo -e "${BLUE}>>> EXTRACTING IN RAM...${NC}"
    tar -zxvf "$TEMP_DIR/singbox.tar.gz" -C "$TEMP_DIR" >/dev/null 2>&1
    
    NEW_BIN=$(find "$TEMP_DIR" -type f -name "sing-box" | head -n 1)
    
    if [ -f "$NEW_BIN" ]; then
        echo -e "${BLUE}>>> INSTALLING TO $BIN_DIR...${NC}"
        # SMART FIX: REMOVE OLD FILE FIRST
        rm -rf "$BIN_DIR/sing-box" >/dev/null 2>&1
        cp -f "$NEW_BIN" "$BIN_DIR/sing-box"
        chmod +x "$BIN_DIR/sing-box"
        echo -e "${GREEN}>>> SING-BOX CORE UPDATED SUCCESSFULLY!${NC}"
        "$BIN_DIR/sing-box" version | head -n 1
    else
        echo -e "${RED}>>> ERROR: BINARY NOT FOUND IN TAR.${NC}"
    fi
    
    restart_passwall
    pause_script
}

update_hysteria() {
    prepare_environment
    echo -e "${YELLOW}>>> STARTING HYSTERIA UPDATE CHECK...${NC}"
    echo -e "${BLUE}>>> ARCH: $HYS_ARCH${NC}"
    
    DOWNLOAD_URL=$(curl -s "https://api.github.com/repos/apernet/hysteria/releases/latest" | grep "browser_download_url" | grep -i "hysteria-linux-$HYS_ARCH" | grep -v "avx" | grep -v ".md5" | grep -v ".sha" | cut -d '"' -f 4 | head -n 1)
    
    if [ -z "$DOWNLOAD_URL" ]; then
        echo -e "${RED}>>> ERROR: COULD NOT FIND HYSTERIA DOWNLOAD LINK.${NC}"
        return
    fi
    
    echo -e "${BLUE}>>> DOWNLOADING BINARY: $DOWNLOAD_URL${NC}"
    echo -e "${BLUE}>>> SAVING TO TEMP SPACE (RAM)...${NC}"
    curl -L -o "$TEMP_DIR/hysteria_new" "$DOWNLOAD_URL"
    
    if [ ! -s "$TEMP_DIR/hysteria_new" ]; then
        echo -e "${RED}>>> ERROR: DOWNLOAD FAILED OR SPACE FULL IN RAM.${NC}"
        return
    fi
    
    stop_passwall
    force_unlock_fs
    emergency_cleaner
    # backup_binary "hysteria"
    
    echo -e "${BLUE}>>> INSTALLING...${NC}"
    # CRITICAL FIX: UNLOCK & FORCE DELETE OLD BINARY
    echo -e "${BLUE}>>> REMOVING OLD BINARY TO FREE SPACE...${NC}"
    rm -rf "$BIN_DIR/hysteria" >/dev/null 2>&1
    
    echo -e "${BLUE}>>> COPYING NEW BINARY...${NC}"
    cp -f "$TEMP_DIR/hysteria_new" "$BIN_DIR/hysteria"
    chmod +x "$BIN_DIR/hysteria"
    
    if [ -f "$BIN_DIR/hysteria" ]; then
        echo -e "${GREEN}>>> HYSTERIA CORE UPDATED SUCCESSFULLY!${NC}"
        "$BIN_DIR/hysteria" version | head -n 1
    else
        echo -e "${RED}>>> ERROR: INSTALLATION FAILED. FILESYSTEM MIGHT BE LOCKED.${NC}"
    fi
    
    restart_passwall
    pause_script
}

update_iran_dat() {
    prepare_environment
    echo -e "${YELLOW}>>> UPDATING IRAN.DAT (GEO DATABASE)...${NC}"
    
    if [ ! -d "$GEO_DIR" ]; then
        mkdir -p "$GEO_DIR"
    fi
    
    echo -e "${BLUE}>>> DOWNLOADING FROM BOOTMORTIS REPO TO RAM...${NC}"
    curl -L -o "$TEMP_DIR/iran.dat" "https://github.com/bootmortis/iran-hosted-domains/releases/latest/download/iran.dat"
    
    if [ -s "$TEMP_DIR/iran.dat" ]; then
        echo -e "${BLUE}>>> MOVING FILE TO $GEO_DIR...${NC}"
        force_unlock_fs
        emergency_cleaner
        rm -f "$GEO_DIR/iran.dat" >/dev/null 2>&1
        mv "$TEMP_DIR/iran.dat" "$GEO_DIR/iran.dat"
        echo -e "${GREEN}>>> IRAN.DAT UPDATED SUCCESSFULLY!${NC}"
    else
        echo -e "${RED}>>> ERROR: DOWNLOAD FAILED OR FILE IS EMPTY.${NC}"
    fi
    
    pause_script
}

ram_cleaner() {
    echo -e "${YELLOW}>>> STARTING RAM CLEANUP...${NC}"
    sync
    echo 3 > /proc/sys/vm/drop_caches
    
    FREE_RAM_AFTER_KB=$(grep MemFree /proc/meminfo | awk '{print $2}')
    FREE_RAM_AFTER=$((FREE_RAM_AFTER_KB / 1024))
    echo -e "${GREEN}>>> RAM CLEANED. FREE MEMORY NOW: ${FREE_RAM_AFTER}MB${NC}"
    pause_script
}

update_luci_pkg() {
    echo -e "${YELLOW}>>> CHECKING FOR LUCI UPDATES...${NC}"
    prepare_environment

    # SUPER CRITICAL FIX FOR 0KB SPACE
    echo -e "${BLUE}>>> CLEANING LISTS...${NC}"
    force_unlock_fs
    emergency_cleaner
    
    echo -e "${BLUE}>>> UPDATING PACKAGE LISTS (IN RAM)...${NC}"
    opkg update --tmp-dir "$TEMP_DIR" >/dev/null 2>&1
    
    UPDATE_AVAIL=$(opkg list-upgradable --tmp-dir "$TEMP_DIR" 2>/dev/null | grep "^luci -")
    
    if [ -n "$UPDATE_AVAIL" ]; then
        echo -e "${YELLOW}>>> UPDATE AVAILABLE: LUCI${NC}"
        echo -e "${RED}>>> CRITICAL DISK MODE: REMOVING OLD TO INSTALL NEW...${NC}"
        
        # LOGIC CHANGE: REMOVE THEN INSTALL (INSTEAD OF UPGRADE)
        echo -e "${BLUE}>>> STEP 1: REMOVING OLD LUCI (KEEPING CONFIG)...${NC}"
        opkg remove luci --force-depends >/dev/null 2>&1
        
        echo -e "${BLUE}>>> STEP 2: INSTALLING NEW LUCI VIA RAM...${NC}"
        opkg install luci --tmp-dir "$TEMP_DIR" --force-space --force-depends
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}>>> LUCI UPDATED SUCCESSFULLY!${NC}"
        else
            echo -e "${RED}>>> ERROR: INSTALL FAILED. ATTEMPTING RETRY...${NC}"
            opkg install luci --tmp-dir "$TEMP_DIR" --force-depends
        fi
    else
        echo -e "${GREEN}>>> LUCI IS ALREADY UP TO DATE.${NC}"
    fi
    
    # FINAL CLEANUP
    rm -rf /var/opkg-lists/* >/dev/null 2>&1
    rm -rf "$TEMP_DIR/*" >/dev/null 2>&1
    pause_script
}

# ==============================================================================
#  5. MENUS
# ==============================================================================

show_main_header() {
    clear
    get_sys_info
    echo -e "${CYAN} +-------------------------------------------------------------+${NC}"
    echo -e "${CYAN} |             ${YELLOW}VIP3R OPENWRT MASTER SCRIPT${CYAN}                     |${NC}"
    echo -e "${CYAN} |                                                             |${NC}"
    echo -e "${CYAN} |        ${GREEN}CREATOR: VIP3R${CYAN}  |  ${BLUE}TELEGRAM: T.ME/CY3ER${CYAN}              |${NC}"
    echo -e "${CYAN} |        ${GREEN}COLLABORATOR: NIMA${CYAN}|  ${BLUE}TELEGRAM: T.ME/#${CYAN}                |${NC}"
    echo -e "${CYAN} |                                                             |${NC}"
    echo -e "${CYAN} +-------------------------------------------------------------+${NC}"
    echo ""
    echo -e "${YELLOW} [DEVICE INFORMATION]${NC}"
    echo -e "${BLUE} MODEL       :${NC} $MODEL"
    echo -e "${BLUE} CPU MODEL   :${NC} $CPU_MODEL"
    echo -e "${BLUE} CPU ARCH    :${NC} $ARCH"
    echo -e "${BLUE} RAM MEMORY  :${NC} USED: ${USED_RAM}MB / TOTAL: ${TOTAL_RAM}MB"
    echo -e "${BLUE} DISK SPACE  :${NC} FREE: ${DISK_FREE} / TOTAL: ${DISK_TOTAL}"
    echo -e "${BLUE} TEMP SPACE  :${NC} FREE: ${TEMP_FREE} / TOTAL: ${TEMP_TOTAL}"
    echo -e "${BLUE} DNS SERVER  :${NC} $DNS_INFO"
    echo -e "${CYAN} -------------------------------------------------------------${NC}"
    echo ""
}

menu_update_cores() {
    get_core_arch
    
    if [ "$XRAY_ARCH" = "UNKNOWN" ]; then
        echo -e "${RED}>>> CRITICAL ERROR: ARCHITECTURE NOT SUPPORTED AUTOMATICALLY.${NC}"
        pause_script
        return
    fi

    while true; do
        clear
        echo -e "${CYAN} --- CORE UPDATE MANAGER ---${NC}"
        echo -e "${BLUE} DETECTED ARCH: $ARCH${NC}"
        echo ""
        echo -e " 1. UPDATE ${GREEN}XRAY CORE${NC}"
        echo -e " 2. UPDATE ${GREEN}SING-BOX CORE${NC}"
        echo -e " 3. UPDATE ${GREEN}HYSTERIA CORE${NC}"
        echo -e " 0. RETURN TO MAIN MENU"
        echo ""
        printf " SELECT OPTION: "
        read SUB_OPT
        
        case $SUB_OPT in
            1) update_xray ;;
            2) update_singbox ;;
            3) update_hysteria ;;
            0) break ;;
            *) echo -e "${RED} INVALID OPTION${NC}" ; sleep 1 ;;
        esac
    done
}

# ==============================================================================
#  6. MAIN LOOP
# ==============================================================================

check_internet_connection

while true; do
    show_main_header
    echo -e "${YELLOW} >> MAIN MENU${NC}"
    echo ""
    echo -e " 1. INSTALL PREREQUISITES (CURL, UNZIP, TAR)"
    echo -e " 2. INSTALL PASSWALL 2"
    echo -e " 3. UPDATE CORES (XRAY, SING-BOX, HYSTERIA)"
    echo -e " 4. INSTALL/UPDATE IRAN.DAT GEO"
    echo -e " 5. RAM CLEANER (OPTIMIZE)"
    echo -e " 6. UPDATE LUCI PACKAGE (SMART CHECK)"
    echo -e " 0. EXIT"
    echo ""
    printf " ENTER YOUR CHOICE: "
    read OPTION
    
    case $OPTION in
        1)
            echo -e "${YELLOW}>>> UPDATING REPOS AND INSTALLING TOOLS...${NC}"
            opkg update
            opkg install curl unzip tar ca-bundle ca-certificates
            # CLEANUP TO SAVE SPACE
            rm -rf /var/opkg-lists/* >/dev/null 2>&1
            echo -e "${GREEN}>>> COMPLETED.${NC}"
            pause_script
            ;;
        2)
            echo -e "${YELLOW}>>> LAUNCHING PASSWALL INSTALLER...${NC}"
            wget -qO- https://saeed9400.github.io/IRAN_Passwall2/install.sh | sh
            pause_script
            ;;
        3) menu_update_cores ;;
        4) update_iran_dat ;;
        5) ram_cleaner ;;
        6) update_luci_pkg ;;
        0) echo -e "${GREEN} GOODBYE VIP3R!${NC}"; exit 0 ;;
        *) echo -e "${RED} INVALID OPTION!${NC}"; sleep 1 ;;
    esac
done