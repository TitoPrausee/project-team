#!/bin/bash
# team-worker.sh
# Worker daemon for Multi-Agent Project Team System
# Processes tasks from backlog and coordinates with orchestrator

set -eo pipefail

# Configuration
TEAM_ROOT="${TEAM_ROOT:-$HOME/project-team}"
BACKLOG="$TEAM_ROOT/backlog"
LOG="/tmp/team-worker.log"
LOCK="/tmp/team-worker.lock"
STATE="$TEAM_ROOT/.team/worker-state.json"

# Henry integration (optional)
HENRY_ROOT="${HENRY_ROOT:-$HOME/Henry}"

# Model configuration
MODEL="${MODEL:-glm-5:cloud}"
MAX_TASK_TIME="${MAX_TASK_TIME:-600}"
PAUSE_BETWEEN="${PAUSE_BETWEEN:-30}"
CONSECUTIVE_LIMIT="${CONSECUTIVE_LIMIT:-5}"
COOLDOWN="${COOLDOWN:-300}"

export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MUTED='\033[90m'
NC='\033[0m'

# Ensure directories
mkdir -p "$BACKLOG"/{todo,doing,done,failed} "$TEAM_ROOT"/{logs/agents,.team}

# Logging
log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${msg}" >> "$LOG"

    case "$level" in
        ERROR) echo -e "${RED}✗${NC} ${msg}" >&2 ;;
        WARN)  echo -e "${YELLOW}!${NC} ${msg}" ;;
        INFO)  echo -e "${BLUE}ℹ${NC} ${msg}" ;;
        OK)    echo -e "${GREEN}✓${NC} ${msg}" ;;
        DEBUG) echo -e "${MUTED}…${NC} ${msg}" ;;
    esac
}

# Single instance lock
acquire_lock() {
    if [ -f "$LOCK" ]; then
        local OLD_PID
        OLD_PID=$(cat "$LOCK" 2>/dev/null)
        if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
            log WARN "Worker already running (PID $OLD_PID)"
            exit 0
        fi
        rm -f "$LOCK"
    fi
    echo $$ > "$LOCK"
    trap 'rm -f "$LOCK"; log INFO "Worker stopped."; exit 0' SIGTERM SIGINT EXIT
}

# Update state
update_state() {
    local status="$1"
    local task="${2:-}"
    local agent="${3:-}"
    local consecutive="${4:-0}"

    jq -n \
        --arg status "$status" \
        --arg task "$task" \
        --arg agent "$agent" \
        --argjson consecutive "$consecutive" \
        --arg timestamp "$(date -Iseconds)" \
        '{
            status: $status,
            current_task: $task,
            current_agent: $agent,
            consecutive_tasks: $consecutive,
            last_update: $timestamp
        }' > "$STATE"
}

# Check if Ollama is available
check_ollama() {
    if command -v ollama &> /dev/null; then
        if pgrep -f "ollama serve" > /dev/null 2>&1 || pgrep -f "ollama" > /dev/null 2>&1; then
            return 0
        fi
        # Try to start Ollama
        log INFO "Starting Ollama..."
        ollama serve &
        sleep 5
        if pgrep -f "ollama" > /dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

# Ensure model is available
ensure_model() {
    if ! ollama list 2>/dev/null | grep -q "$MODEL"; then
        log INFO "Pulling model $MODEL..."
        ollama pull "$MODEL" || {
            log WARN "Could not pull model $MODEL, will use fallback"
        }
    fi
}

# Determine task type
get_task_type() {
    local task_file="$1"

    # Check if JSON with type field
    if [[ "$task_file" == *.json ]]; then
        local task_type
        task_type=$(jq -r '.type // "single"' "$task_file" 2>/dev/null || echo "single")
        echo "$task_type"
        return
    fi

    # Check first line for project marker (Henry pattern)
    local first_line
    first_line=$(head -1 "$task_file" 2>/dev/null)

    if [[ "$first_line" == /* ]]; then
        echo "project"
        return
    fi

    # Default
    echo "single"
}

# Route task to appropriate handler
route_task() {
    local task_file="$1"
    local task_type
    task_type=$(get_task_type "$task_file")

    log DEBUG "Task type: $task_type for $(basename "$task_file")"

    case "$task_type" in
        "pipeline")
            # Use orchestrator for pipeline tasks
            log INFO "Routing to orchestrator for pipeline task"
            "$TEAM_ROOT/coordinator/orchestrator.sh" run &
            ;;
        "project")
            # Use Henry project agent pattern
            log INFO "Routing to project handler"
            handle_project_task "$task_file"
            ;;
        *)
            # Single agent task
            log INFO "Routing to single agent handler"
            handle_single_task "$task_file"
            ;;
    esac
}

# Handle single agent task
handle_single_task() {
    local task_file="$1"
    local task_name
    task_name=$(basename "$task_file" | sed 's/\.[^.]*$//')

    log INFO "Processing single task: $task_name"

    # Move to doing
    local doing_file
    if [[ "$task_file" == *.json ]]; then
        mv "$task_file" "$BACKLOG/doing/${task_name}.json"
        doing_file="$BACKLOG/doing/${task_name}.json"
    else
        mv "$task_file" "$BACKLOG/doing/${task_name}.md"
        doing_file="$BACKLOG/doing/${task_name}.md"
    fi

    update_state "processing" "$task_name" "determining" 0

    # Determine agent from task metadata
    local agent
    if [[ "$doing_file" == *.json ]]; then
        agent=$(jq -r '.agent // "entwickler"' "$doing_file" 2>/dev/null || echo "entwickler")
    else
        # Parse agent from markdown header
        agent=$(grep -i "^agent:" "$doing_file" 2>/dev/null | head -1 | cut -d: -f2- | tr -d ' ' || echo "entwickler")
        [ -z "$agent" ] && agent="entwickler"
    fi

    log INFO "Assigned to agent: $agent"
    update_state "processing" "$task_name" "$agent" 0

    # Run agent
    local exit_code=0
    run_single_agent "$agent" "$doing_file" || exit_code=$?

    # Handle result
    if [ $exit_code -eq 0 ]; then
        mv "$doing_file" "$BACKLOG/done/"
        log OK "Task completed: $task_name"
    elif [ $exit_code -eq 2 ]; then
        mv "$doing_file" "$BACKLOG/failed/${task_name}.timeout"
        log ERROR "Task timed out: $task_name"
    else
        mv "$doing_file" "$BACKLOG/failed/${task_name}.error"
        log ERROR "Task failed: $task_name"
    fi

    return $exit_code
}

# Run single agent
run_single_agent() {
    local agent="$1"
    local task_file="$2"

    local agent_workspace="$TEAM_ROOT/agents/$agent/workspace"
    local agent_log="$TEAM_ROOT/logs/agents/$agent.log"

    mkdir -p "$agent_workspace"

    # Prepare input
    local input_file="$agent_workspace/input.json"

    if [[ "$task_file" == *.json ]]; then
        # JSON task
        jq '{task: ., mode: "single"}' "$task_file" > "$input_file"
    else
        # Markdown task
        local description
        description=$(cat "$task_file")
        jq -n --arg desc "$description" '{task: {description: $desc}, mode: "single"}' > "$input_file"
    fi

    # Run agent
    log INFO "Running agent $agent with model $MODEL..."

    local start_time
    start_time=$(date +%s)

    # Use orchestrator for agent execution
    local output_file="$agent_workspace/output.json"

    if command -v openclaw &> /dev/null; then
        timeout "$MAX_TASK_TIME" openclaw agent run \
            --model "$MODEL" \
            --workspace "$agent_workspace" \
            --input "$input_file" \
            --output "$output_file" \
            2>&1 | tee -a "$agent_log" || {
            local exit_code=$?
            if [ $exit_code -eq 124 ]; then
                return 2
            fi
            return $exit_code
        }
    else
        # Fallback: direct ollama call
        local prompt
        prompt=$(jq -r '.task.description // .task // "No task description"' "$input_file")

        local response
        response=$(timeout "$MAX_TASK_TIME" ollama run "$MODEL" "$prompt" 2>&1 | tee -a "$agent_log") || {
            local exit_code=$?
            if [ $exit_code -eq 124 ]; then
                return 2
            fi
            return $exit_code
        }

        # Create output
        jq -n \
            --arg agent "$agent" \
            --arg response "$response" \
            --arg timestamp "$(date -Iseconds)" \
            '{
                from_agent: $agent,
                to_agent: "complete",
                timestamp: $timestamp,
                status: "READY",
                payload: {
                    result: $response
                }
            }' > "$output_file"
    fi

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    log OK "Agent $agent finished (duration: ${duration}s)"
    return 0
}

# Handle project task (Henry pattern)
handle_project_task() {
    local task_file="$1"
    local task_name
    task_name=$(basename "$task_file" | sed 's/\.[^.]*$//')

    log INFO "Processing project task: $task_name"

    # Extract repo and description (Henry format)
    local repo
    local description
    repo=$(head -1 "$task_file")
    description=$(tail -n +2 "$task_file")

    # Move to doing
    mv "$task_file" "$BACKLOG/doing/${task_name}.md"
    local doing_file="$BACKLOG/doing/${task_name}.md"

    update_state "processing" "$task_name" "project" 0

    # Check if Henry project agent exists
    if [ -x "$HENRY_ROOT/henry-project-agent.sh" ]; then
        log INFO "Using Henry project agent..."
        local result_file="/tmp/project-result.md"

        timeout "$MAX_TASK_TIME" bash "$HENRY_ROOT/henry-project-agent.sh" \
            "$repo" "$description" "$result_file" || {
            local exit_code=$?
            mv "$doing_file" "$BACKLOG/failed/${task_name}.error"
            return $exit_code
        }

        mv "$doing_file" "$BACKLOG/done/"
        log OK "Project task completed: $task_name"
        return 0
    fi

    # Fallback: Use regular agent
    log WARN "Henry project agent not found, using regular agent"
    mv "$doing_file" "$BACKLOG/todo/${task_name}.md"
    return 1
}

# Cooldown after consecutive tasks
cooldown() {
    local consecutive="$1"

    if [ "$consecutive" -ge "$CONSECUTIVE_LIMIT" ]; then
        log INFO "Cooldown after $consecutive consecutive tasks (${COOLDOWN}s)..."
        sleep "$COOLDOWN"
        echo 0
    else
        echo "$consecutive"
    fi
}

# Main worker loop
main() {
    log "=========================================="
    log INFO "Project Team Worker started (PID $$)"
    log "=========================================="

    acquire_lock

    log INFO "Configuration:"
    log INFO "  TEAM_ROOT: $TEAM_ROOT"
    log INFO "  MODEL: $MODEL"
    log INFO "  MAX_TASK_TIME: ${MAX_TASK_TIME}s"
    log INFO "  CONSECUTIVE_LIMIT: $CONSECUTIVE_LIMIT"

    # Check dependencies
    if ! command -v jq &> /dev/null; then
        log ERROR "jq not found, cannot continue"
        exit 1
    fi

    # Check Ollama
    if ! check_ollama; then
        log WARN "Ollama not available, agent execution may fail"
    else
        ensure_model
    fi

    local consecutive=0

    while true; do
        # Update state
        update_state "idle" "" "" "$consecutive"

        # Health check
        if ! pgrep -f "ollama" > /dev/null 2>&1; then
            log WARN "Ollama not running, waiting..."
            sleep 60
            continue
        fi

        # Get next task
        local task
        task=$(ls -1 "$BACKLOG/todo/"*.{md,json} 2>/dev/null | sort | head -1) || true

        if [ -z "$task" ]; then
            sleep 60
            continue
        fi

        # Process task
        consecutive=$((consecutive + 1))
        update_state "processing" "$(basename "$task")" "routing" "$consecutive"

        route_task "$task" || {
            log ERROR "Task routing failed: $task"
        }

        # Cooldown check
        consecutive=$(cooldown "$consecutive")

        sleep "$PAUSE_BETWEEN"
    done
}

# CLI interface
case "${1:-}" in
    "run")
        main
        ;;
    "status")
        if [ -f "$STATE" ]; then
            cat "$STATE" | jq .
        else
            echo '{"status": "not_running"}'
        fi
        ;;
    "check")
        echo "Checking worker prerequisites..."
        echo ""

        echo "[1] Dependencies:"
        command -v jq &> /dev/null && echo "  ✓ jq" || echo "  ✗ jq (missing)"
        command -v ollama &> /dev/null && echo "  ✓ ollama" || echo "  ✗ ollama (missing)"

        echo ""
        echo "[2] Directories:"
        [ -d "$BACKLOG/todo" ] && echo "  ✓ $BACKLOG/todo" || echo "  ✗ $BACKLOG/todo"
        [ -d "$BACKLOG/doing" ] && echo "  ✓ $BACKLOG/doing" || echo "  ✗ $BACKLOG/doing"
        [ -d "$BACKLOG/done" ] && echo "  ✓ $BACKLOG/done" || echo "  ✗ $BACKLOG/done"
        [ -d "$BACKLOG/failed" ] && echo "  ✓ $BACKLOG/failed" || echo "  ✗ $BACKLOG/failed"

        echo ""
        echo "[3] Model:"
        ollama list 2>/dev/null | grep -q "$MODEL" && echo "  ✓ $MODEL available" || echo "  ✗ $MODEL not found"
        ;;
    *)
        echo "Usage: $0 {run|status|check}"
        echo ""
        echo "Commands:"
        echo "  run     - Start the worker daemon"
        echo "  status  - Show worker status"
        echo "  check   - Check prerequisites"
        exit 1
        ;;
esac