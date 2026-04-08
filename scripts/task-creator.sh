#!/bin/bash
# task-creator.sh
# Create and manage tasks for the Multi-Agent Project Team System

set -euo pipefail

TEAM_ROOT="${TEAM_ROOT:-$HOME/project-team}"
BACKLOG="$TEAM_ROOT/backlog/todo"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MUTED='\033[90m'
BOLD='\033[1m'
NC='\033[0m'

# Ensure directories exist
mkdir -p "$BACKLOG"

# Usage
usage() {
    echo -e "${BOLD}Task Creator${NC} - Create and manage tasks for Project Team"
    echo ""
    echo -e "${BLUE}Usage:${NC}"
    echo "  $0 <command> [options]"
    echo ""
    echo -e "${BLUE}Commands:${NC}"
    echo -e "  ${GREEN}single${NC} <agent> <description>     Create a single-agent task"
    echo -e "  ${GREEN}pipeline${NC} <description>           Create a multi-agent pipeline task"
    echo -e "  ${GREEN}project${NC} <repo> <description>     Create a coding project task"
    echo -e "  ${GREEN}list${NC}                            List all pending tasks"
    echo -e "  ${GREEN}show${NC} <task-id>                  Show task details"
    echo -e "  ${GREEN}cancel${NC} <task-id>                Cancel/delete a task"
    echo -e "  ${GREEN}status${NC}                          Show backlog status"
    echo ""
    echo -e "${BLUE}Agents:${NC}"
    echo "  architekt-pm    - Architecture, Planning, Coordination"
    echo "  entwickler      - Code Implementation, Bug Fixes"
    echo "  tester-qa       - Testing, QA, Validation"
    echo "  dokumentator    - Documentation, README, API Docs"
    echo "  git-manager     - Git Operations, Issues, PRs"
    echo ""
    echo -e "${BLUE}Examples:${NC}"
    echo "  $0 single entwickler 'Fix the login bug'"
    echo "  $0 pipeline 'Create a new REST API endpoint'"
    echo "  $0 project ~/my-repo 'Add authentication'"
    exit 1
}

# Create single-agent task
create_single_task() {
    local agent="$1"
    shift
    local description="$*"

    # Validate agent
    case "$agent" in
        architekt-pm|entwickler|tester-qa|dokumentator|git-manager)
            ;;
        *)
            echo -e "${RED}Error: Invalid agent '${agent}'${NC}"
            echo "Valid agents: architekt-pm, entwickler, tester-qa, dokumentator, git-manager"
            exit 1
            ;;
    esac

    local timestamp
    timestamp=$(date +%s)
    local task_file="$BACKLOG/${timestamp}-single-${agent}.json"

    jq -n \
        --arg type "single" \
        --arg agent "$agent" \
        --arg desc "$description" \
        --arg timestamp "$(date -Iseconds)" \
        --arg id "TASK-$timestamp" \
        '{
            id: $id,
            type: $type,
            agent: $agent,
            description: $desc,
            created: $timestamp,
            status: "todo",
            priority: "medium"
        }' > "$task_file"

    echo -e "${GREEN}✓${NC} Created single task for ${BOLD}$agent${NC}"
    echo -e "  ID: ${MUTED}$timestamp${NC}"
    echo -e "  File: ${MUTED}$task_file${NC}"
    echo -e "  Description: $description"
}

# Create pipeline task (all agents in sequence)
create_pipeline_task() {
    local description="$*"

    local timestamp
    timestamp=$(date +%s)
    local task_file="$BACKLOG/${timestamp}-pipeline.json"

    jq -n \
        --arg type "pipeline" \
        --arg desc "$description" \
        --arg timestamp "$(date -Iseconds)" \
        --arg id "TASK-$timestamp" \
        --argjson pipeline '["architekt-pm", "entwickler", "tester-qa", "dokumentator", "git-manager"]' \
        '{
            id: $id,
            type: $type,
            description: $desc,
            pipeline: $pipeline,
            current_stage: 0,
            created: $timestamp,
            status: "todo",
            priority: "medium",
            handoffs: []
        }' > "$task_file"

    echo -e "${GREEN}✓${NC} Created ${BOLD}pipeline${NC} task"
    echo -e "  ID: ${MUTED}$timestamp${NC}"
    echo -e "  File: ${MUTED}$task_file${NC}"
    echo -e "  Pipeline: architekt-pm → entwickler → tester-qa → dokumentator → git-manager"
    echo -e "  Description: $description"
}

# Create project task (Henry pattern)
create_project_task() {
    local repo="$1"
    shift
    local description="$*"

    # Validate repo
    if [ ! -d "$repo/.git" ]; then
        echo -e "${RED}Error: '$repo' is not a git repository${NC}"
        exit 1
    fi

    local timestamp
    timestamp=$(date +%s)
    local task_file="$BACKLOG/${timestamp}-project.md"

    # Henry format: first line is repo path, rest is description
    {
        echo "$repo"
        echo "$description"
    } > "$task_file"

    echo -e "${GREEN}✓${NC} Created ${BOLD}project${NC} task"
    echo -e "  ID: ${MUTED}$timestamp${NC}"
    echo -e "  File: ${MUTED}$task_file${NC}"
    echo -e "  Repository: $repo"
    echo -e "  Description: $description"
}

# List all pending tasks
list_tasks() {
    echo -e "${BOLD}=== Pending Tasks ===${NC}"
    echo ""

    local count=0
    for f in "$BACKLOG"/*.md "$BACKLOG"/*.json; do
        [ -f "$f" ] || continue
        [ -f "$f" ] || continue
        ((count++)) || true

        local name
        name=$(basename "$f")
        local id
        id=$(echo "$name" | sed 's/\.[^.]*$//')

        if [[ "$name" == *"-pipeline"* ]]; then
            local desc
            desc=$(jq -r '.description // "No description"' "$f" 2>/dev/null || head -2 "$f" | tail -1)
            echo -e "  ${BLUE}[PIPELINE]${NC} $id"
            echo -e "      ${MUTED}$desc${NC}"
        elif [[ "$name" == *"-project"* ]]; then
            local repo
            repo=$(head -1 "$f" 2>/dev/null)
            echo -e "  ${YELLOW}[PROJECT]${NC} $id"
            echo -e "      ${MUTED}Repo: $repo${NC}"
        else
            local agent
            agent=$(jq -r '.agent // "unknown"' "$f" 2>/dev/null || echo "unknown")
            local desc
            desc=$(jq -r '.description // "No description"' "$f" 2>/dev/null || cat "$f")
            echo -e "  ${GREEN}[SINGLE:${agent}]${NC} $id"
            echo -e "      ${MUTED}$desc${NC}"
        fi
        echo ""
    done

    if [ "$count" -eq 0 ]; then
        echo -e "  ${MUTED}(No pending tasks)${NC}"
    fi

    echo -e "${MUTED}Total: $count task(s)${NC}"
}

# Show task details
show_task() {
    local task_id="$1"

    # Find task
    local task_file
    task_file=$(ls "$BACKLOG"/${task_id}* 2>/dev/null | head -1)

    if [ -z "$task_file" ]; then
        echo -e "${RED}Error: Task '$task_id' not found${NC}"
        exit 1
    fi

    echo -e "${BOLD}=== Task Details ===${NC}"
    echo ""

    if [[ "$task_file" == *.json ]]; then
        jq '.' "$task_file"
    else
        cat "$task_file"
    fi
}

# Cancel/delete a task
cancel_task() {
    local task_id="$1"

    # Find task
    local task_file
    task_file=$(ls "$BACKLOG"/${task_id}* 2>/dev/null | head -1)

    if [ -z "$task_file" ]; then
        echo -e "${RED}Error: Task '$task_id' not found${NC}"
        exit 1
    fi

    # Move to failed with cancelled prefix
    local failed_dir="$TEAM_ROOT/backlog/failed"
    mkdir -p "$failed_dir"

    local basename
    basename=$(basename "$task_file")
    mv "$task_file" "$failed_dir/cancelled-$basename"

    echo -e "${YELLOW}✗${NC} Task ${BOLD}$task_id${NC} cancelled"
    echo -e "  Moved to: ${MUTED}$failed_dir/cancelled-$basename${NC}"
}

# Show backlog status
show_status() {
    echo -e "${BOLD}=== Backlog Status ===${NC}"
    echo ""

    local todo doing done failed

    todo=$(ls -1 "$TEAM_ROOT/backlog/todo/"*.{md,json} 2>/dev/null | wc -l | tr -d ' ')
    doing=$(ls -1 "$TEAM_ROOT/backlog/doing/"*.{md,json} 2>/dev/null | wc -l | tr -d ' ')
    done=$(ls -1 "$TEAM_ROOT/backlog/done/"*.{md,json} 2>/dev/null | wc -l | tr -d ' ')
    failed=$(ls -1 "$TEAM_ROOT/backlog/failed/"*.{md,json} 2>/dev/null | wc -l | tr -d ' ')

    echo -e "  ${BLUE}TODO:${NC}    $todo"
    echo -e "  ${YELLOW}DOING:${NC}   $doing"
    echo -e "  ${GREEN}DONE:${NC}    $done"
    echo -e "  ${RED}FAILED:${NC}  $failed"
    echo ""

    # Pending handoffs
    local pending
    pending=$(ls -1 "$TEAM_ROOT/backlog/handoffs/pending/"*.json 2>/dev/null | wc -l | tr -d ' ')
    echo -e "  ${MUTED}Pending Handoffs:${NC} $pending"

    # Worker status
    local worker_state="$TEAM_ROOT/.team/worker-state.json"
    if [ -f "$worker_state" ]; then
        echo ""
        echo -e "${BOLD}Worker Status:${NC}"
        jq '.' "$worker_state" 2>/dev/null || echo "  ${MUTED}(Unable to read state)${NC}"
    fi

    # Orchestrator status
    local orchestrator_state="$TEAM_ROOT/.team/orchestrator-state.json"
    if [ -f "$orchestrator_state" ]; then
        echo ""
        echo -e "${BOLD}Orchestrator Status:${NC}"
        jq '.' "$orchestrator_state" 2>/dev/null || echo "  ${MUTED}(Unable to read state)${NC}"
    fi
}

# Main CLI
case "${1:-}" in
    single)
        shift
        [ $# -lt 2 ] && { echo -e "${RED}Error: Missing arguments${NC}"; usage; }
        create_single_task "$@"
        ;;
    pipeline)
        shift
        [ $# -lt 1 ] && { echo -e "${RED}Error: Missing description${NC}"; usage; }
        create_pipeline_task "$@"
        ;;
    project)
        shift
        [ $# -lt 2 ] && { echo -e "${RED}Error: Missing arguments${NC}"; usage; }
        create_project_task "$@"
        ;;
    list)
        list_tasks
        ;;
    show)
        shift
        [ $# -lt 1 ] && { echo -e "${RED}Error: Missing task-id${NC}"; usage; }
        show_task "$1"
        ;;
    cancel)
        shift
        [ $# -lt 1 ] && { echo -e "${RED}Error: Missing task-id${NC}"; usage; }
        cancel_task "$1"
        ;;
    status)
        show_status
        ;;
    *)
        usage
        ;;
esac