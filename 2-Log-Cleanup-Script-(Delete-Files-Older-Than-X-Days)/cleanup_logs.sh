#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

LOG_DIR="/var/log/myapp"
DAYS=30
DRY_RUN=false

echo -e "${BLUE}=== Log Cleanup Utility ===${NC}"

while getopts "d:n" opt; do
    case $opt in
        d) DAYS=$OPTARG ;;
        n) DRY_RUN=true ;;
        *) echo "Usage: $0 [-d days] [-n (dry run)]"; exit 1 ;;
    esac
done

echo -e "Target directory: ${CYAN}$LOG_DIR${NC}"
echo -e "Delete files older than: ${YELLOW}$DAYS days${NC}"
echo -e "Dry run mode: ${CYAN}$DRY_RUN${NC}"

if [ ! -d "$LOG_DIR" ]; then
    echo -e "${RED}Error: Directory $LOG_DIR does not exist${NC}"
    exit 1
fi

# Find files
echo -e "\n${BLUE}Scanning...${NC}"
find "$LOG_DIR" -type f -name "*.log" -mtime +$DAYS -print0 | while IFS= read -r -d '' file; do
    size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
    size_mb=$(echo "scale=2; $size/1024/1024" | bc)
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY RUN]${NC} Would delete: $(basename "$file") (${size_mb}MB)"
    else
        echo -e "${RED}Deleting:${NC} $(basename "$file") (${size_mb}MB)"
        rm -f "$file"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Deleted successfully${NC}"
        else
            echo -e "${RED}✗ Failed to delete${NC}"
        fi
    fi
done

echo -e "\n${GREEN}Cleanup operation completed.${NC}"