#!/bin/bash
# orchestrator.sh
# Main coordination script for Multi-Agent Project Team System
# Routes tasks through the agent pipeline and manages handoffs

set -eo pipefail

# Configuration
TEAM_ROOT="${TEAM_ROOT:-$HOME/project-team}"
BACKLOG="$TEAM_ROOT/backlog"
HANDOFFS="$TEAM_ROOT/backlog/handoffs"
CONFIG="$TEAM_ROOT/config"
LOG="$TEAM_ROOT/logs/orchestrator.log"
LOCK="/tmp/project-team-orchestrator.lock"
STATE="$TEAM_ROOT/.team/orchestrator-state.json"

# Model configuration
MODEL="${MODEL:-glm-5:cloud}"
MAX_TASK_TIME="${MAX_TASK_TIME:-600}"
MAX_PIPELINE_TIME="${MAX_PIPELINE_TIME:-3600}"
PAUSE_BETWEEN="${PAUSE_BETWEEN:-30}"

# Agent pipeline order (bash 3 compatible - no associative arrays)
get_next_agent() {
    case "$1" in
        "architekt-pm") echo "entwickler" ;;
        "entwickler") echo "tester-qa" ;;
        "tester-qa") echo "dokumentator" ;;
        "dokumentator") echo "git-manager" ;;
        "git-manager") echo "complete" ;;
        *) echo "complete" ;;
    esac
}

get_agent_position() {
    case "$1" in
        "architekt-pm") echo "1" ;;
        "entwickler") echo "2" ;;
        "tester-qa") echo "3" ;;
        "dokumentator") echo "4" ;;
        "git-manager") echo "5" ;;
        *) echo "0" ;;
    esac
}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Ensure directories exist
mkdir -p "$BACKLOG"/{todo,doing,done,failed} "$HANDOFFS"/{pending,archive} "$TEAM_ROOT/logs/agents" "$TEAM_ROOT/.team"

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
    esac
}

# Single instance lock
acquire_lock() {
    if [ -f "$LOCK" ]; then
        local OLD_PID
        OLD_PID=$(cat "$LOCK" 2>/dev/null)
        if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
            log WARN "Orchestrator already running (PID $OLD_PID)"
            exit 0
        fi
        rm -f "$LOCK"
    fi
    echo $$ > "$LOCK"
    trap 'rm -f "$LOCK"; log INFO "Orchestrator stopped."; exit 0' SIGTERM SIGINT EXIT
}

# Validate handoff payload against schema
validate_handoff() {
    local handoff_file="$1"

    if [ ! -f "$handoff_file" ]; then
        log ERROR "Handoff file not found: $handoff_file"
        return 1
    fi

    # Check if file is valid JSON
    if ! jq '.' "$handoff_file" > /dev/null 2>&1; then
        log ERROR "Invalid JSON in handoff file"
        return 1
    fi

    # Check required fields
    local required_fields=("from_agent" "to_agent" "timestamp" "status" "payload")
    for field in "${required_fields[@]}"; do
        if ! jq -e ".$field" "$handoff_file" > /dev/null 2>&1; then
            log ERROR "Missing required field: $field"
            return 1
        fi
    done

    # Check agent is valid
    local from_agent
    from_agent=$(jq -r '.from_agent' "$handoff_file")
    if [[ ! "$from_agent" =~ ^(architekt-pm|entwickler|tester-qa|dokumentator|git-manager|user)$ ]]; then
        log ERROR "Invalid from_agent: $from_agent"
        return 1
    fi

    # Check status is valid
    local status
    status=$(jq -r '.status' "$handoff_file")
    if [[ ! "$status" =~ ^(READY|BLOCKED|IN_REVISION|APPROVED|DEPLOYED)$ ]]; then
        log ERROR "Invalid status: $status"
        return 1
    fi

    log OK "Handoff validated: $from_agent -> $(jq -r '.to_agent' "$handoff_file")"
    return 0
}

# Get next agent in pipeline
get_next_agent() {
    local current_agent="$1"
    get_next_agent "$current_agent"
}

# Determine which agent should handle a task
select_agent_for_task() {
    local task_file="$1"

    # Check for existing handoff (continue pipeline)
    local pending_handoff
    pending_handoff=$(ls -t "$HANDOFFS/pending/"*.json 2>/dev/null | head -1) || true

    if [ -n "$pending_handoff" ]; then
        local from_agent
        from_agent=$(jq -r '.from_agent' "$pending_handoff")
        get_next_agent "$from_agent"
        return
    fi

    # Check task type for routing
    local task_type
    task_type=$(jq -r '.type // "default"' "$task_file" 2>/dev/null || echo "default")

    case "$task_type" in
        "architecture"|"planning")
            echo "architekt-pm"
            ;;
        "implementation"|"bugfix"|"feature")
            echo "entwickler"
            ;;
        "testing"|"qa")
            echo "tester-qa"
            ;;
        "documentation"|"readme")
            echo "dokumentator"
            ;;
        "git"|"release"|"pr")
            echo "git-manager"
            ;;
        "pipeline"|"full")
            echo "architekt-pm"  # Start pipeline from beginning
            ;;
        *)
            echo "architekt-pm"  # Default to architect for planning
            ;;
    esac
}

# Run agent with task
run_agent() {
    local agent="$1"
    local task_file="$2"
    local handoff_file="${3:-}"

    local agent_name
    case "$agent" in
        "architekt-pm") agent_name="Architekt/PM" ;;
        "entwickler") agent_name="Entwickler" ;;
        "tester-qa") agent_name="Tester/QA" ;;
        "dokumentator") agent_name="Dokumentator" ;;
        "git-manager") agent_name="Git Manager" ;;
        *) agent_name="$agent" ;;
    esac

    log INFO "Starting agent: $agent_name for task $(basename "$task_file")"

    local agent_config="$TEAM_ROOT/agents/$agent/config.json"
    local agent_workspace="$TEAM_ROOT/agents/$agent/workspace"
    local agent_log="$TEAM_ROOT/logs/agents/$agent.log"

    # Ensure workspace exists
    mkdir -p "$agent_workspace"

    # Prepare input for agent
    local input_file="$agent_workspace/input.json"

    if [ -n "$handoff_file" ] && [ -f "$handoff_file" ]; then
        # Continue from previous handoff
        jq -n \
            --arg task "$(cat "$task_file")" \
            --slurpfile handoff "$handoff_file" \
            '{task: $task, handoff: $handoff[0], mode: "pipeline"}' > "$input_file"
    else
        # Fresh start
        local task_content
        if [[ "$task_file" == *.json ]]; then
            task_content=$(cat "$task_file")
        else
            task_content=$(jq -Rs '{description: .}' < "$task_file")
        fi

        jq -n \
            --argjson task "$task_content" \
            '{task: $task, mode: "single"}' > "$input_file"
    fi

    # Run agent via openclaw/ollama
    local output_file="$agent_workspace/output.json"
    local start_time
    start_time=$(date +%s)

    log INFO "Running $agent_name with model $MODEL..."

    # Execute agent (this would be replaced with actual openclaw/ollama call)
    # For now, this is a placeholder that would be integrated with openclaw
    if command -v openclaw &> /dev/null; then
        timeout "$MAX_TASK_TIME" openclaw agent run \
            --agent-config "$agent_config" \
            --model "$MODEL" \
            --workspace "$agent_workspace" \
            --input "$input_file" \
            --output "$output_file" \
            2>&1 | tee -a "$agent_log" || {
            local exit_code=$?
            if [ $exit_code -eq 124 ]; then
                log ERROR "Agent $agent_name timed out after ${MAX_TASK_TIME}s"
                return 2
            fi
            log ERROR "Agent $agent_name failed with exit code $exit_code"
            return $exit_code
        }
    else
        # Fallback: Use jq to create a structured response
        log WARN "OpenClaw not found, creating placeholder output"
        jq -n \
            --arg from "$agent" \
            --arg to "$(get_next_agent "$agent")" \
            --arg timestamp "$(date -Iseconds)" \
            --arg task "$(basename "$task_file" .md)" \
            '{
                from_agent: $from,
                to_agent: $to,
                timestamp: $timestamp,
                status: "READY",
                task_reference: $task,
                iteration: 1,
                payload: {
                    type: "placeholder",
                    message: "Agent execution requires openclaw integration"
                },
                metadata: {
                    duration_seconds: 0,
                    model: "glm-5-cloud"
                }
            }' > "$output_file"
    fi

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Update output with metadata
    if [ -f "$output_file" ]; then
        local tmp_output="${output_file}.tmp"
        jq --arg duration "$duration" --arg model "$MODEL" \
            '.metadata.duration_seconds = ($duration | tonumber) | .metadata.model = $model' \
            "$output_file" > "$tmp_output"
        mv "$tmp_output" "$output_file"
    fi

    # Validate handoff output
    if [ -f "$output_file" ]; then
        if validate_handoff "$output_file"; then
            # Archive handoff
            local archive_name
            archive_name="$(date +%Y%m%d_%H%M%S)_${agent}_$(basename "$task_file" | sed 's/\.[^.]*$//').json"
            mv "$output_file" "$HANDOFFS/pending/$archive_name"

            log OK "Agent $agent_name completed successfully (duration: ${duration}s)"
            return 0
        else
            log ERROR "Agent $agent_name produced invalid handoff"
            return 1
        fi
    else
        log ERROR "Agent $agent_name did not produce output"
        return 1
    fi
}

# Process a single task through the pipeline
process_task() {
    local task_file="$1"
    local task_name
    task_name=$(basename "$task_file" | sed 's/\.[^.]*$//')

    log INFO "Processing task: $task_name"

    # Move task to doing
    mv "$task_file" "$BACKLOG/doing/${task_name}.md" 2>/dev/null || \
        mv "$task_file" "$BACKLOG/doing/${task_name}.json" 2>/dev/null || true

    local doing_file="$BACKLOG/doing/${task_name}.md"
    [ -f "$doing_file" ] || doing_file="$BACKLOG/doing/${task_name}.json"

    # Check for pending handoff (continue pipeline)
    local pending_handoff
    pending_handoff=$(ls -t "$HANDOFFS/pending/"*.json 2>/dev/null | head -1) || true

    local start_agent
    if [ -n "$pending_handoff" ]; then
        # Continue from handoff
        local from_agent
        from_agent=$(jq -r '.from_agent' "$pending_handoff")
        start_agent=$(get_next_agent "$from_agent")
        log INFO "Continuing pipeline from $from_agent -> $start_agent"
    else
        # Start new pipeline
        start_agent=$(select_agent_for_task "$doing_file")
        log INFO "Starting new pipeline with $start_agent"
    fi

    # Run agent
    local exit_code=0
    if [ -n "$pending_handoff" ]; then
        run_agent "$start_agent" "$doing_file" "$pending_handoff" || exit_code=$?
    else
        run_agent "$start_agent" "$doing_file" || exit_code=$?
    fi

    # Handle result
    if [ $exit_code -eq 0 ]; then
        # Check if pipeline is complete
        if [ "$start_agent" = "git-manager" ] || [ "$(get_next_agent "$start_agent")" = "complete" ]; then
            mv "$doing_file" "$BACKLOG/done/" 2>/dev/null || true
            # Archive handoffs
            for hf in "$HANDOFFS/pending/"*.json; do
                [ -f "$hf" ] && mv "$hf" "$HANDOFFS/archive/" 2>/dev/null || true
            done
            log OK "Pipeline complete for task: $task_name"
        fi
        return 0
    elif [ $exit_code -eq 2 ]; then
        # Timeout
        mv "$doing_file" "$BACKLOG/failed/${task_name}.timeout" 2>/dev/null || true
        return 2
    else
        # Failure
        mv "$doing_file" "$BACKLOG/failed/${task_name}.error" 2>/dev/null || true
        return 1
    fi
}

# Update state file
update_state() {
    local status="$1"
    local task="$2"
    local agent="$3"

    jq -n \
        --arg status "$status" \
        --arg task "$task" \
        --arg agent "$agent" \
        --arg timestamp "$(date -Iseconds)" \
        '{
            status: $status,
            current_task: $task,
            current_agent: $agent,
            last_update: $timestamp
        }' > "$STATE"
}

# Main orchestrator loop
main() {
    log INFO "=========================================="
    log INFO "Project Team Orchestrator started (PID $$)"
    log INFO "=========================================="

    acquire_lock

    log INFO "Configuration:"
    log INFO "  TEAM_ROOT: $TEAM_ROOT"
    log INFO "  MODEL: $MODEL"
    log INFO "  MAX_TASK_TIME: ${MAX_TASK_TIME}s"
    log INFO "  MAX_PIPELINE_TIME: ${MAX_PIPELINE_TIME}s"

    while true; do
        # Health check
        if ! command -v jq &> /dev/null; then
            log ERROR "jq not found, cannot continue"
            exit 1
        fi

        # Update state
        update_state "idle" "" ""

        # Check for pending handoffs first (continue pipeline)
        local pending_handoff
        pending_handoff=$(ls -t "$HANDOFFS/pending/"*.json 2>/dev/null | head -1) || true

        if [ -n "$pending_handoff" ]; then
            log INFO "Found pending handoff: $(basename "$pending_handoff")"
            local from_agent
            from_agent=$(jq -r '.from_agent' "$pending_handoff")
            local task_ref
            task_ref=$(jq -r '.task_reference // "unknown"' "$pending_handoff")

            update_state "processing" "$task_ref" "$from_agent"

            # Find the doing task
            local doing_task
            doing_task=$(ls -1 "$BACKLOG/doing/"* 2>/dev/null | head -1) || true

            if [ -n "$doing_task" ]; then
                process_task "$doing_task" || {
                    log ERROR "Failed to process task: $doing_task"
                }
            else
                log WARN "No doing task found for pending handoff"
                # Archive orphan handoff
                mv "$pending_handoff" "$HANDOFFS/archive/orphan_$(date +%s).json"
            fi

            sleep "$PAUSE_BETWEEN"
            continue
        fi

        # Check for new tasks
        local new_task
        new_task=$(ls -1 "$BACKLOG/todo/"*.{md,json} 2>/dev/null | sort | head -1) || true

        if [ -n "$new_task" ]; then
            log INFO "Found new task: $(basename "$new_task")"
            update_state "processing" "$(basename "$new_task")" "starting"
            process_task "$new_task" || {
                log ERROR "Failed to process task: $new_task"
            }
            sleep "$PAUSE_BETWEEN"
            continue
        fi

        # No tasks - idle
        update_state "idle" "" ""
        sleep 60
    done
}

# CLI interface
case "${1:-}" in
    "run")
        main
        ;;
    "validate")
        shift
        validate_handoff "$1"
        ;;
    "next-agent")
        shift
        get_next_agent "$1"
        ;;
    "select-agent")
        shift
        select_agent_for_task "$1"
        ;;
    "status")
        if [ -f "$STATE" ]; then
            cat "$STATE" | jq .
        else
            echo '{"status": "not_running"}'
        fi
        ;;
    *)
        echo "Usage: $0 {run|validate|next-agent|select-agent|status}"
        echo ""
        echo "Commands:"
        echo "  run          - Start the orchestrator daemon"
        echo "  validate     - Validate a handoff file"
        echo "  next-agent   - Get next agent in pipeline"
        echo "  select-agent  - Select agent for a task"
        echo "  status       - Show orchestrator status"
        exit 1
        ;;
esac