#!/bin/bash

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

THRESHOLD=80
EMAIL="admin@company.com"
PARTITION="/"

# Check disk usage
USAGE=$(df -h $PARTITION | awk 'NR==2 {print $5}' | sed 's/%//')

echo -e "${BLUE}=== Disk Usage Monitor ===${NC}"
echo -e "Current usage: ${YELLOW}${USAGE}%${NC}"
echo -e "Threshold: ${GREEN}${THRESHOLD}%${NC}"

if [ $USAGE -gt $THRESHOLD ]; then
    echo -e "${RED}WARNING: Disk usage exceeds threshold!${NC}"
    MESSAGE="Alert: Disk usage on $(hostname) is at ${USAGE}% (threshold: ${THRESHOLD}%)"
    
    # Send email (requires mailutils configured)
    echo "$MESSAGE" | mail -s "Disk Alert $(hostname)" $EMAIL
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Alert email sent to $EMAIL${NC}"
    else
        echo -e "${RED}Failed to send email${NC}"
    fi
else
    echo -e "${GREEN}Disk usage is within normal limits.${NC}"
fi