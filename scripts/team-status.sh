#!/bin/bash
# team-status.sh
# Check status of Multi-Agent Project Team System

set -eo pipefail

TEAM_ROOT="${TEAM_ROOT:-$HOME/project-team}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MUTED='\033[90m'
BOLD='\033[1m'
NC='\033[0m'

# Print header
print_header() {
    echo -e "${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║          Multi-Agent Project Team Status                   ║${NC}"
    echo -e "${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Check Ollama status
check_ollama() {
    echo -e "${BOLD}[Ollama]${NC}"

    if pgrep -f "ollama" > /dev/null 2>&1; then
        echo -e "  Status: ${GREEN}● Running${NC}"

        # Check model availability
        if command -v ollama &> /dev/null; then
            local models
            models=$(ollama list 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
            echo -e "  Models:  ${MUTED}$models available${NC}"

            # Check for glm-5:cloud
            if ollama list 2>/dev/null | grep -q "glm-5"; then
                echo -e "  Primary: ${GREEN}glm-5:cloud ✓${NC}"
            else
                echo -e "  Primary: ${YELLOW}fallback model${NC}"
            fi
        fi
    else
        echo -e "  Status: ${RED}● Not Running${NC}"
        echo -e "  ${MUTED}Start with: ollama serve${NC}"
    fi
    echo ""
}

# Check worker status
check_worker() {
    echo -e "${BOLD}[Worker]${NC}"

    local worker_pid
    worker_pid=$(pgrep -f "team-worker.sh" 2>/dev/null | head -1)

    if [ -n "$worker_pid" ]; then
        echo -e "  Status: ${GREEN}● Running${NC} (PID $worker_pid)"

        # Check state file
        local state_file="$TEAM_ROOT/.team/worker-state.json"
        if [ -f "$state_file" ]; then
            local status task agent consecutive
            status=$(jq -r '.status // "unknown"' "$state_file" 2>/dev/null)
            task=$(jq -r '.current_task // "none"' "$state_file" 2>/dev/null)
            agent=$(jq -r '.current_agent // "none"' "$state_file" 2>/dev/null)
            consecutive=$(jq -r '.consecutive_tasks // 0' "$state_file" 2>/dev/null)

            echo -e "  State:   ${MUTED}$status${NC}"
            [ "$task" != "none" ] && [ "$task" != "null" ] && echo -e "  Task:    ${MUTED}$task${NC}"
            [ "$agent" != "none" ] && [ "$agent" != "null" ] && echo -e "  Agent:   ${MUTED}$agent${NC}"
            echo -e "  Streak:  ${MUTED}$consecutive consecutive tasks${NC}"
        fi
    else
        echo -e "  Status: ${RED}● Not Running${NC}"
        echo -e "  ${MUTED}Start with: ./scripts/team-worker.sh run${NC}"
    fi
    echo ""
}

# Check orchestrator status
check_orchestrator() {
    echo -e "${BOLD}[Orchestrator]${NC}"

    local orch_pid
    orch_pid=$(pgrep -f "orchestrator.sh" 2>/dev/null | head -1)

    if [ -n "$orch_pid" ]; then
        echo -e "  Status: ${GREEN}● Running${NC} (PID $orch_pid)"

        # Check state file
        local state_file="$TEAM_ROOT/.team/orchestrator-state.json"
        if [ -f "$state_file" ]; then
            local status task agent
            status=$(jq -r '.status // "unknown"' "$state_file" 2>/dev/null)
            task=$(jq -r '.current_task // "none"' "$state_file" 2>/dev/null)
            agent=$(jq -r '.current_agent // "none"' "$state_file" 2>/dev/null)

            echo -e "  State:   ${MUTED}$status${NC}"
            [ "$task" != "none" ] && [ "$task" != "null" ] && echo -e "  Task:    ${MUTED}$task${NC}"
            [ "$agent" != "none" ] && [ "$agent" != "null" ] && echo -e "  Agent:   ${MUTED}$agent${NC}"
        fi
    else
        echo -e "  Status: ${YELLOW}● Not Running${NC}"
        echo -e "  ${MUTED}Start with: ./coordinator/orchestrator.sh run${NC}"
    fi
    echo ""
}

# Check backlog status
check_backlog() {
    echo -e "${BOLD}[Backlog]${NC}"

    local todo doing done failed

    todo=$(ls -1 "$TEAM_ROOT/backlog/todo/"*.{md,json} 2>/dev/null | wc -l | tr -d ' ')
    doing=$(ls -1 "$TEAM_ROOT/backlog/doing/"*.{md,json} 2>/dev/null | wc -l | tr -d ' ')
    done=$(ls -1 "$TEAM_ROOT/backlog/done/"*.{md,json} 2>/dev/null | wc -l | tr -d ' ')
    failed=$(ls -1 "$TEAM_ROOT/backlog/failed/"*.{md,json} 2>/dev/null | wc -l | tr -d ' ')

    echo -e "  ${BLUE}TODO:${NC}    $todo pending"
    echo -e "  ${YELLOW}DOING:${NC}   $doing in progress"
    echo -e "  ${GREEN}DONE:${NC}    $done completed"
    echo -e "  ${RED}FAILED:${NC}  $failed failed"
    echo ""

    # Show recent tasks
    if [ "$todo" -gt 0 ]; then
        echo -e "  ${MUTED}Next tasks:${NC}"
        ls -1t "$TEAM_ROOT/backlog/todo/"*.{md,json} 2>/dev/null | head -3 | while read -r f; do
            local name
            name=$(basename "$f" | sed 's/\.[^.]*$//')
            echo -e "    ${MUTED}• $name${NC}"
        done
    fi
    echo ""
}

# Check pending handoffs
check_handoffs() {
    echo -e "${BOLD}[Pending Handoffs]${NC}"

    local pending
    pending=$(ls -1 "$TEAM_ROOT/backlog/handoffs/pending/"*.json 2>/dev/null | wc -l | tr -d ' ')

    if [ "$pending" -gt 0 ]; then
        echo -e "  Count:   ${YELLOW}$pending pending${NC}"
        echo ""

        # Show details
        ls -1t "$TEAM_ROOT/backlog/handoffs/pending/"*.json 2>/dev/null | head -3 | while read -r f; do
            local from to status task
            from=$(jq -r '.from_agent // "unknown"' "$f" 2>/dev/null)
            to=$(jq -r '.to_agent // "unknown"' "$f" 2>/dev/null)
            status=$(jq -r '.status // "unknown"' "$f" 2>/dev/null)
            task=$(jq -r '.task_reference // "unknown"' "$f" 2>/dev/null)

            echo -e "  ${MUTED}• $from → $to${NC}"
            echo -e "    ${MUTED}Task: $task | Status: $status${NC}"
        done
    else
        echo -e "  Count:   ${GREEN}0 pending${NC}"
    fi
    echo ""
}

# Check agent workspaces
check_agents() {
    echo -e "${BOLD}[Agent Workspaces]${NC}"

    local agents=("architekt-pm" "entwickler" "tester-qa" "dokumentator" "git-manager")

    for agent in "${agents[@]}"; do
        local workspace="$TEAM_ROOT/agents/$agent/workspace"
        local log="$TEAM_ROOT/logs/agents/$agent.log"

        local workspace_files=0
        local log_lines=0

        [ -d "$workspace" ] && workspace_files=$(ls -1 "$workspace" 2>/dev/null | wc -l | tr -d ' ')
        [ -f "$log" ] && log_lines=$(wc -l < "$log" | tr -d ' ')

        echo -e "  ${MUTED}$agent:${NC} $workspace_files files in workspace"

        if [ -f "$log" ] && [ "$log_lines" -gt 0 ]; then
            local last_entry
            last_entry=$(tail -1 "$log" 2>/dev/null | head -c 60)
            echo -e "    ${MUTED}Last log: $last_entry...${NC}"
        fi
    done
    echo ""
}

# Check memory
check_memory() {
    echo -e "${BOLD}[Memory]${NC}"

    local team_memory="$TEAM_ROOT/shared/memory/TEAM_MEMORY.md"
    local shared_context="$TEAM_ROOT/shared/context/project-context.json"

    if [ -f "$team_memory" ]; then
        local lines
        lines=$(wc -l < "$team_memory" | tr -d ' ')
        echo -e "  Team Memory:  ${MUTED}$lines lines${NC}"
    else
        echo -e "  Team Memory:  ${YELLOW}(not initialized)${NC}"
    fi

    if [ -f "$shared_context" ]; then
        local project
        project=$(jq -r '.project_name // "unknown"' "$shared_context" 2>/dev/null)
        echo -e "  Project:      ${MUTED}$project${NC}"
    else
        echo -e "  Project:      ${YELLOW}(no active project)${NC}"
    fi
    echo ""
}

# Check system resources
check_resources() {
    echo -e "${BOLD}[System Resources]${NC}"

    # Disk usage
    local disk_usage
    disk_usage=$(df -h "$TEAM_ROOT" 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')
    if [ "$disk_usage" -gt 90 ]; then
        echo -e "  Disk:     ${RED}${disk_usage}% used${NC}"
    elif [ "$disk_usage" -gt 80 ]; then
        echo -e "  Disk:     ${YELLOW}${disk_usage}% used${NC}"
    else
        echo -e "  Disk:     ${GREEN}${disk_usage}% used${NC}"
    fi

    # Memory usage (macOS and Linux compatible)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        local mem_info
        mem_info=$(vm_stat 2>/dev/null | head -5)
        echo -e "  Memory:   ${MUTED}(see Activity Monitor)${NC}"
    else
        local mem_usage
        mem_usage=$(free 2>/dev/null | awk '/Mem:/ {printf "%d", $3/$2 * 100}')
        if [ "$mem_usage" -gt 90 ]; then
            echo -e "  Memory:   ${RED}${mem_usage}% used${NC}"
        elif [ "$mem_usage" -gt 80 ]; then
            echo -e "  Memory:   ${YELLOW}${mem_usage}% used${NC}"
        else
            echo -e "  Memory:   ${GREEN}${mem_usage}% used${NC}"
        fi
    fi

    # Load average
    local load
    load=$(uptime 2>/dev/null | awk -F'load averages:' '{print $2}' | awk '{print $1}' | tr -d ',')
    echo -e "  Load:     ${MUTED}$load${NC}"
    echo ""
}

# Quick actions
print_actions() {
    echo -e "${BOLD}Quick Actions${NC}"
    echo -e "  ${MUTED}./scripts/task-creator.sh pipeline \"Your task\"${NC}  - Create new task"
    echo -e "  ${MUTED}./scripts/task-creator.sh list${NC}                  - List pending tasks"
    echo -e "  ${MUTED}./scripts/team-worker.sh run${NC}                   - Start worker"
    echo -e "  ${MUTED}./coordinator/orchestrator.sh run${NC}              - Start orchestrator"
    echo ""
}

# Main
main() {
    print_header
    check_ollama
    check_worker
    check_orchestrator
    check_backlog
    check_handoffs
    check_agents
    check_memory
    check_resources
    print_actions
}

# CLI interface
case "${1:-}" in
    --json)
        # Output as JSON
        {
            echo '{'
            echo '"ollama_running": '$(pgrep -f "ollama" > /dev/null && echo 'true' || echo 'false')','
            echo '"worker_running": '$(pgrep -f "team-worker.sh" > /dev/null && echo 'true' || echo 'false')','
            echo '"orchestrator_running": '$(pgrep -f "orchestrator.sh" > /dev/null && echo 'true' || echo 'false')','
            todo=$(ls -1 "$TEAM_ROOT/backlog/todo/"*.{md,json} 2>/dev/null | wc -l | tr -d ' ')
            doing=$(ls -1 "$TEAM_ROOT/backlog/doing/"*.{md,json} 2>/dev/null | wc -l | tr -d ' ')
            done=$(ls -1 "$TEAM_ROOT/backlog/done/"*.{md,json} 2>/dev/null | wc -l | tr -d ' ')
            failed=$(ls -1 "$TEAM_ROOT/backlog/failed/"*.{md,json} 2>/dev/null | wc -l | tr -d ' ')
            echo "\"backlog\": {\"todo\": $todo, \"doing\": $doing, \"done\": $done, \"failed\": $failed}"
            echo '}'
        } | jq '.'
        ;;
    --short)
        # Short output
        todo=$(ls -1 "$TEAM_ROOT/backlog/todo/"*.{md,json} 2>/dev/null | wc -l | tr -d ' ')
        doing=$(ls -1 "$TEAM_ROOT/backlog/doing/"*.{md,json} 2>/dev/null | wc -l | tr -d ' ')
        done=$(ls -1 "$TEAM_ROOT/backlog/done/"*.{md,json} 2>/dev/null | wc -l | tr -d ' ')
        worker=$(pgrep -f "team-worker.sh" > /dev/null && echo "✓" || echo "✗")
        ollama=$(pgrep -f "ollama" > /dev/null && echo "✓" || echo "✗")
        echo "Ollama:$ollama Worker:$worker | TODO:$todo DOING:$doing DONE:$done"
        ;;
    *)
        main
        ;;
esac