#!/bin/bash
# start-team.sh
# Start the Multi-Agent Project Team System

set -euo pipefail

TEAM_ROOT="${TEAM_ROOT:-$HOME/project-team}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
MUTED='\033[90m'
NC='\033[0m'

echo -e "${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║       Multi-Agent Project Team System                      ║${NC}"
echo -e "${BOLD}║       Starting...                                          ║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check dependencies
echo -e "${BLUE}[1/6]${NC} Checking dependencies..."

check_command() {
    if command -v "$1" &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} $1"
        return 0
    else
        echo -e "  ${RED}✗${NC} $1 ${MUTED}(missing)${NC}"
        return 1
    fi
}

missing=0
check_command jq || ((missing++))
check_command bash || ((missing++))
check_command git || ((missing++))

if [ $missing -gt 0 ]; then
    echo -e "${RED}Error: Missing required dependencies${NC}"
    echo -e "Install with: ${MUTED}brew install jq git${NC}"
    exit 1
fi
echo ""

# Check Ollama
echo -e "${BLUE}[2/6]${NC} Checking Ollama..."

if ! command -v ollama &> /dev/null; then
    echo -e "  ${YELLOW}!${NC} Ollama not found"
    echo -e "  ${MUTED}Install from: https://ollama.com${NC}"
else
    if pgrep -f "ollama" > /dev/null; then
        echo -e "  ${GREEN}✓${NC} Ollama running"
    else
        echo -e "  ${YELLOW}!${NC} Starting Ollama..."
        ollama serve &
        sleep 3
        if pgrep -f "ollama" > /dev/null; then
            echo -e "  ${GREEN}✓${NC} Ollama started"
        else
            echo -e "  ${RED}✗${NC} Failed to start Ollama"
        fi
    fi
fi
echo ""

# Ensure model is available
echo -e "${BLUE}[3/6]${NC} Checking model availability..."

MODEL="${MODEL:-glm-5:cloud}"
if command -v ollama &> /dev/null; then
    if ollama list 2>/dev/null | grep -q "$MODEL"; then
        echo -e "  ${GREEN}✓${NC} Model $MODEL available"
    else
        echo -e "  ${YELLOW}!${NC} Pulling model $MODEL..."
        ollama pull "$MODEL" || {
            echo -e "  ${YELLOW}!${NC} Could not pull $MODEL, will use fallback"
        }
    fi
else
    echo -e "  ${YELLOW}!${NC} Skipping model check (Ollama not available)"
fi
echo ""

# Create directory structure
echo -e "${BLUE}[4/6]${NC} Creating directory structure..."

mkdir -p "$TEAM_ROOT"/agents/{architekt-pm,entwickler,tester-qa,dokumentator,git-manager}/{workspace,memory} \
    "$TEAM_ROOT"/backlog/{todo,doing,done,failed,handoffs/{pending,archive}} \
    "$TEAM_ROOT"/coordinator \
    "$TEAM_ROOT"/shared/{context,memory,templates,skills} \
    "$TEAM_ROOT"/scripts \
    "$TEAM_ROOT"/config \
    "$TEAM_ROOT"/logs/agents \
    "$TEAM_ROOT"/results \
    "$TEAM_ROOT"/.team

echo -e "  ${GREEN}✓${NC} Directories created"
echo ""

# Verify configuration files
echo -e "${BLUE}[5/6]${NC} Verifying configuration..."

config_files=(
    "$TEAM_ROOT/config/agent-definitions.json"
    "$TEAM_ROOT/config/model-config.json"
    "$TEAM_ROOT/shared/templates/handoff-schema.json"
    "$TEAM_ROOT/coordinator/orchestrator.sh"
    "$TEAM_ROOT/scripts/team-worker.sh"
    "$TEAM_ROOT/scripts/task-creator.sh"
    "$TEAM_ROOT/scripts/team-status.sh"
)

missing_configs=0
for f in "${config_files[@]}"; do
    if [ -f "$f" ]; then
        echo -e "  ${GREEN}✓${NC} $(basename "$f")"
    else
        echo -e "  ${RED}✗${NC} $(basename "$f") ${MUTED}(missing)${NC}"
        ((missing_configs++))
    fi
done

if [ $missing_configs -gt 0 ]; then
    echo -e "${YELLOW}Warning: Some configuration files are missing${NC}"
fi
echo ""

# Start services
echo -e "${BLUE}[6/6]${NC} Starting services..."

# Kill existing processes
pkill -f "team-worker.sh" 2>/dev/null || true
pkill -f "orchestrator.sh" 2>/dev/null || true
sleep 1

# Start worker
if [ -x "$TEAM_ROOT/scripts/team-worker.sh" ]; then
    echo -e "  ${GREEN}→${NC} Starting worker..."
    nohup "$TEAM_ROOT/scripts/team-worker.sh" run > /tmp/team-worker.log 2>&1 &
    echo -e "  ${GREEN}✓${NC} Worker started"
else
    echo -e "  ${YELLOW}!${NC} Worker script not executable"
fi

# Start orchestrator
if [ -x "$TEAM_ROOT/coordinator/orchestrator.sh" ]; then
    echo -e "  ${GREEN}→${NC} Starting orchestrator..."
    nohup "$TEAM_ROOT/coordinator/orchestrator.sh" run > /tmp/orchestrator.log 2>&1 &
    echo -e "  ${GREEN}✓${NC} Orchestrator started"
else
    echo -e "  ${YELLOW}!${NC} Orchestrator script not executable"
fi
echo ""

# Final status
echo -e "${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║       System Started Successfully                           ║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${BLUE}Commands:${NC}"
echo -e "  ${MUTED}./scripts/task-creator.sh pipeline \"Your task\"${NC}  - Create new task"
echo -e "  ${MUTED}./scripts/task-creator.sh list${NC}                  - List pending tasks"
echo -e "  ${MUTED}./scripts/team-status.sh${NC}                       - Show system status"
echo -e "  ${MUTED}./scripts/team-worker.sh status${NC}               - Check worker status"
echo -e "  ${MUTED}./coordinator/orchestrator.sh status${NC}           - Check orchestrator status"
echo ""
echo -e "${BLUE}Logs:${NC}"
echo -e "  ${MUTED}/tmp/team-worker.log${NC}       - Worker log"
echo -e "  ${MUTED}/tmp/orchestrator.log${NC}      - Orchestrator log"
echo -e "  ${MUTED}$TEAM_ROOT/logs/agents/${NC}  - Agent logs"
echo ""
echo -e "${BLUE}Config:${NC}"
echo -e "  ${MUTED}TEAM_ROOT=$TEAM_ROOT${NC}"
echo -e "  ${MUTED}MODEL=$MODEL${NC}"
echo ""