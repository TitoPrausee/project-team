#!/bin/bash
# chat.sh - Interaktiver Chat mit dem Multi-Agent Project Team
# Ermöglicht direkte Kommunikation mit den Agenten

set -eo pipefail

# Agent-Emojis und Namen (bash 3 compatible)
get_agent_emoji() {
    case "$1" in
        architekt-pm) echo "🏗️" ;;
        entwickler) echo "💻" ;;
        tester-qa) echo "🧪" ;;
        dokumentator) echo "📝" ;;
        git-manager) echo "🔀" ;;
        system) echo "⚙️" ;;
        user) echo "👤" ;;
        *) echo "🤖" ;;
    esac
}

get_agent_name() {
    case "$1" in
        architekt-pm) echo "Architekt/PM" ;;
        entwickler) echo "Entwickler" ;;
        tester-qa) echo "Tester/QA" ;;
        dokumentator) echo "Dokumentator" ;;
        git-manager) echo "Git Manager" ;;
        system) echo "System" ;;
        *) echo "$1" ;;
    esac
}

TEAM_ROOT="${TEAM_ROOT:-$HOME/project-team}"
MODEL="${MODEL:-glm-5:cloud}"
BACKLOG="$TEAM_ROOT/backlog"
HANDOFFS="$TEAM_ROOT/backlog/handoffs"
LOG="$TEAM_ROOT/logs/chat.log"

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
MUTED='\033[90m'
NC='\033[0m'

# Verzeichnisse sicherstellen
mkdir -p "$BACKLOG"/{todo,doing,done,failed} "$HANDOFFS"/{pending,archive} "$TEAM_ROOT/logs" 2>/dev/null

# Logging
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"
}

# Chat-Banner anzeigen
show_banner() {
    clear
    echo -e "${CYAN}"
    echo -e "╔════════════════════════════════════════════════════════════╗"
    echo -e "║     🤖  Multi-Agent Project Team Chat                      ║"
    echo -e "║     ─────────────────────────────────────────────────────   ║"
    echo -e "║     5 Agenten bereit für deine Aufgaben                    ║"
    echo -e "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    echo -e "${MUTED}Agenten:${NC}"
    echo -e "  $(get_agent_emoji architekt-pm) ${BOLD}Architekt/PM${NC}     - Planung & Architektur"
    echo -e "  $(get_agent_emoji entwickler) ${BOLD}Entwickler${NC}       - Code & Implementation"
    echo -e "  $(get_agent_emoji tester-qa) ${BOLD}Tester/QA${NC}        - Tests & Validierung"
    echo -e "  $(get_agent_emoji dokumentator) ${BOLD}Dokumentator${NC}     - Doku & README"
    echo -e "  $(get_agent_emoji git-manager) ${BOLD}Git Manager${NC}      - Git & Issues"
    echo ""
    echo -e "${MUTED}Befehle:${NC}"
    echo -e "  ${CYAN}/pipeline${NC} <beschreibung>  - Neue Pipeline-Task (alle 5 Agenten)"
    echo -e "  ${CYAN}/single${NC} <agent> <task>    - Single-Agent Task"
    echo -e "  ${CYAN}/status${NC}                  - System-Status"
    echo -e "  ${CYAN}/tasks${NC}                   - Aktuelle Tasks"
    echo -e "  ${CYAN}/history${NC}                 - Letzte Handoffs"
    echo -e "  ${CYAN}/clear${NC}                   - Chat leeren"
    echo -e "  ${CYAN}/help${NC}                    - Diese Hilfe"
    echo -e "  ${CYAN}/exit${NC}                    - Chat beenden"
    echo ""
    echo -e "${MUTED}────────────────────────────────────────────────────────────${NC}"
    echo ""
}

# Nachricht formatieren
print_message() {
    local sender="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%H:%M:%S')

    local emoji=$(get_agent_emoji "$sender")
    local name=$(get_agent_name "$sender")

    case "$sender" in
        "user")
            echo -e "${GREEN}${emoji} ${BOLD}Du${NC} ${MUTED}[$timestamp]${NC}"
            ;;
        "system")
            echo -e "${YELLOW}${emoji} ${BOLD}$name${NC} ${MUTED}[$timestamp]${NC}"
            ;;
        "architekt-pm"|"entwickler"|"tester-qa"|"dokumentator"|"git-manager")
            echo -e "${CYAN}${emoji} ${BOLD}$name${NC} ${MUTED}[$timestamp]${NC}"
            ;;
        *)
            echo -e "${MUTED}${emoji} $name${NC} ${MUTED}[$timestamp]${NC}"
            ;;
    esac

    # Nachricht mit Einrückung
    echo "$message" | while IFS= read -r line; do
        echo -e "  $line"
    done
    echo ""
}

# System-Status anzeigen
show_status() {
    print_message "system" "System-Status:"

    # Ollama
    if pgrep -f "ollama" > /dev/null 2>&1; then
        echo -e "  ${GREEN}●${NC} Ollama: ${GREEN}Running${NC}"
    else
        echo -e "  ${RED}●${NC} Ollama: ${RED}Not Running${NC}"
    fi

    # Worker
    local worker_pid
    worker_pid=$(pgrep -f "team-worker" 2>/dev/null | head -1)
    if [ -n "$worker_pid" ]; then
        echo -e "  ${GREEN}●${NC} Worker: ${GREEN}Running${NC} (PID $worker_pid)"
    else
        echo -e "  ${RED}●${NC} Worker: ${RED}Not Running${NC}"
    fi

    # Orchestrator
    local orch_pid
    orch_pid=$(pgrep -f "orchestrator" 2>/dev/null | head -1)
    if [ -n "$orch_pid" ]; then
        echo -e "  ${GREEN}●${NC} Orchestrator: ${GREEN}Running${NC} (PID $orch_pid)"
    else
        echo -e "  ${RED}●${NC} Orchestrator: ${RED}Not Running${NC}"
    fi

    # Backlog
    local todo doing done failed
    todo=$(ls -1 "$BACKLOG/todo/"*.json 2>/dev/null | wc -l | tr -d ' ')
    doing=$(ls -1 "$BACKLOG/doing/"*.json 2>/dev/null | wc -l | tr -d ' ')
    done=$(ls -1 "$BACKLOG/done/"*.json 2>/dev/null | wc -l | tr -d ' ')
    failed=$(ls -1 "$BACKLOG/failed/"*.json 2>/dev/null | wc -l | tr -d ' ')

    echo ""
    echo -e "  ${BLUE}Backlog:${NC}"
    echo -e "    TODO: $todo  |  DOING: $doing  |  DONE: $done  |  FAILED: $failed"
}

# Aktuelle Tasks anzeigen
show_tasks() {
    print_message "system" "Aktuelle Tasks:"

    local count=0

    # Todo Tasks
    for f in "$BACKLOG/todo"/*.json; do
        [ -f "$f" ] || continue
        ((count++)) || true
        local name type desc
        name=$(basename "$f" .json)
        type=$(jq -r '.type // "unknown"' "$f" 2>/dev/null || echo "unknown")
        desc=$(jq -r '.description[:60] // "No description"' "$f" 2>/dev/null || echo "No description")
        echo -e "  ${BLUE}●${NC} ${BOLD}$name${NC} ($type)"
        echo -e "    ${MUTED}$desc...${NC}"
    done 2>/dev/null || true

    # Doing Tasks
    for f in "$BACKLOG/doing"/*.json; do
        [ -f "$f" ] || continue
        ((count++)) || true
        local name agent
        name=$(basename "$f" .json)
        agent=$(jq -r '.current_agent // "unknown"' "$f" 2>/dev/null || echo "unknown")
        echo -e "  ${YELLOW}►${NC} ${BOLD}$name${NC} (processing by $(get_agent_name "$agent"))"
    done 2>/dev/null || true

    if [ "$count" -eq 0 ]; then
        echo -e "  ${MUTED}Keine aktiven Tasks${NC}"
    fi
}

# Letzte Handoffs anzeigen
show_history() {
    print_message "system" "Letzte Handoffs:"

    local count=0
    for f in $(ls -t "$HANDOFFS/archive"/*.json 2>/dev/null | head -5); do
        [ -f "$f" ] || continue
        ((count++)) || true
        local from to timestamp
        from=$(jq -r '.from_agent // "unknown"' "$f" 2>/dev/null)
        to=$(jq -r '.to_agent // "unknown"' "$f" 2>/dev/null)
        timestamp=$(jq -r '.timestamp // "unknown"' "$f" 2>/dev/null)
        local from_name=$(get_agent_name "$from")
        local to_name=$(get_agent_name "$to")
        local from_emoji=$(get_agent_emoji "$from")
        local to_emoji=$(get_agent_emoji "$to")

        echo -e "  ${from_emoji} $from_name → ${to_emoji} $to_name ${MUTED}($timestamp)${NC}"
    done

    if [ "$count" -eq 0 ]; then
        echo -e "  ${MUTED}Keine Handoffs vorhanden${NC}"
    fi
}

# Pipeline-Task erstellen
create_pipeline_task() {
    local description="$*"

    if [ -z "$description" ]; then
        print_message "system" "❌ Bitte eine Beschreibung angeben: /pipeline <beschreibung>"
        return 1
    fi

    local timestamp id task_file
    timestamp=$(date +%s)
    id="TASK-$timestamp"
    task_file="$BACKLOG/todo/${timestamp}-pipeline.json"

    jq -n \
        --arg id "$id" \
        --arg type "pipeline" \
        --arg desc "$description" \
        --arg timestamp "$(date -Iseconds)" \
        --argjson pipeline '["architekt-pm", "entwickler", "tester-qa", "dokumentator", "git-manager"]' \
        '{
            id: $id,
            type: $type,
            description: $desc,
            pipeline: $pipeline,
            current_stage: 0,
            created: $timestamp,
            status: "todo"
        }' > "$task_file"

    print_message "system" "✅ Pipeline-Task erstellt: $id"
    echo -e "  ${MUTED}Beschreibung: $description${NC}"
    echo -e "  ${MUTED}Pipeline: Architekt/PM → Entwickler → Tester/QA → Dokumentator → Git Manager${NC}"

    log "Created pipeline task: $id - $description"
}

# Single-Agent Task erstellen
create_single_task() {
    local agent="$1"
    shift
    local description="$*"

    # Agent validieren
    case "$agent" in
        architekt-pm|entwickler|tester-qa|dokumentator|git-manager)
            ;;
        *)
            print_message "system" "❌ Ungültiger Agent: $agent"
            echo -e "  ${MUTED}Gültige Agenten: architekt-pm, entwickler, tester-qa, dokumentator, git-manager${NC}"
            return 1
            ;;
    esac

    if [ -z "$description" ]; then
        print_message "system" "❌ Bitte eine Beschreibung angeben: /single <agent> <beschreibung>"
        return 1
    fi

    local timestamp id task_file
    timestamp=$(date +%s)
    id="TASK-$timestamp"
    task_file="$BACKLOG/todo/${timestamp}-single-${agent}.json"

    jq -n \
        --arg id "$id" \
        --arg type "single" \
        --arg agent "$agent" \
        --arg desc "$description" \
        --arg timestamp "$(date -Iseconds)" \
        '{
            id: $id,
            type: $type,
            agent: $agent,
            description: $desc,
            created: $timestamp,
            status: "todo"
        }' > "$task_file"

    local agent_name=$(get_agent_name "$agent")
    local agent_emoji=$(get_agent_emoji "$agent")

    print_message "system" "✅ Single-Task erstellt: $id"
    echo -e "  ${agent_emoji} ${BOLD}$agent_name${NC}"
    echo -e "  ${MUTED}Beschreibung: $description${NC}"

    log "Created single task for $agent: $id - $description"
}

# Direkte Nachricht an Agent
chat_with_agent() {
    local agent="$1"
    local message="$2"

    # Agent validieren
    case "$agent" in
        architekt-pm|entwickler|tester-qa|dokumentator|git-manager)
            ;;
        *)
            print_message "system" "❌ Ungültiger Agent: $agent"
            return 1
            ;;
    esac

    local agent_name=$(get_agent_name "$agent")
    local agent_emoji=$(get_agent_emoji "$agent")

    print_message "system" "💬 Sende Nachricht an ${agent_emoji} $agent_name..."

    # Erstelle eine Single-Task für die Nachricht
    local timestamp task_file
    timestamp=$(date +%s)
    task_file="$BACKLOG/todo/${timestamp}-chat-${agent}.json"

    jq -n \
        --arg type "chat" \
        --arg agent "$agent" \
        --arg msg "$message" \
        --arg timestamp "$(date -Iseconds)" \
        '{
            type: $type,
            agent: $agent,
            message: $msg,
            created: $timestamp,
            status: "todo"
        }' > "$task_file"

    # Simuliere Agent-Antwort (wird normalerweise von Ollama generiert)
    print_message "$agent" "Ich habe deine Nachricht erhalten: \"$message\"\n\n(Benutze /pipeline oder /single für vollständige Tasks)"
}

# Hilfe anzeigen
show_help() {
    print_message "system" "Verfügbare Befehle:"
    echo ""
    echo -e "  ${CYAN}/pipeline${NC} <beschreibung>"
    echo -e "    ${MUTED}Erstellt eine Task, die von allen 5 Agenten bearbeitet wird${NC}"
    echo -e "    ${MUTED}Beispiel: /pipeline Erstelle eine REST API für Benutzer${NC}"
    echo ""
    echo -e "  ${CYAN}/single${NC} <agent> <beschreibung>"
    echo -e "    ${MUTED}Erstellt eine Task für einen einzelnen Agenten${NC}"
    echo -e "    ${MUTED}Agenten: architekt-pm, entwickler, tester-qa, dokumentator, git-manager${NC}"
    echo -e "    ${MUTED}Beispiel: /single entwickler Fixe den Login-Bug${NC}"
    echo ""
    echo -e "  ${CYAN}@<agent>${NC} <nachricht>"
    echo -e "    ${MUTED}Sende eine direkte Nachricht an einen Agenten${NC}"
    echo -e "    ${MUTED}Beispiel: @entwickler Wie läuft der Code?${NC}"
    echo ""
    echo -e "  ${CYAN}/status${NC}  - Zeigt den System-Status"
    echo -e "  ${CYAN}/tasks${NC}   - Zeigt aktive Tasks"
    echo -e "  ${CYAN}/history${NC} - Zeigt letzte Handoffs"
    echo -e "  ${CYAN}/clear${NC}   - Leert den Chat"
    echo -e "  ${CYAN}/help${NC}    - Zeigt diese Hilfe"
    echo -e "  ${CYAN}/exit${NC}    - Beendet den Chat"
}

# User-Input verarbeiten
process_input() {
    local input="$1"

    # Leere Eingabe
    [ -z "$input" ] && return 0

    # Befehle erkennen
    case "$input" in
        /exit|/quit|/q)
            print_message "system" "👋 Auf Wiedersehen! Bis zum nächsten Mal."
            exit 0
            ;;
        /clear)
            clear
            show_banner
            return 0
            ;;
        /help|/?)
            show_help
            return 0
            ;;
        /status)
            show_status
            return 0
            ;;
        /tasks)
            show_tasks
            return 0
            ;;
        /history)
            show_history
            return 0
            ;;
        /pipeline\ *)
            local desc="${input#/pipeline }"
            create_pipeline_task "$desc"
            return 0
            ;;
        /single\ *)
            local rest="${input#/single }"
            local agent="${rest%% *}"
            local desc="${rest#* }"
            create_single_task "$agent" "$desc"
            return 0
            ;;
        @*)
            local rest="${input#@}"
            local agent="${rest%% *}"
            local msg="${rest#* }"
            chat_with_agent "$agent" "$msg"
            return 0
            ;;
        /*)
            print_message "system" "❓ Unbekannter Befehl: $input"
            echo -e "  ${MUTED}Benutze /help für eine Liste aller Befehle${NC}"
            return 0
            ;;
    esac

    # Normale Nachricht - erstelle Pipeline-Task
    print_message "user" "$input"
    print_message "system" "🔄 Erstelle Pipeline-Task aus deiner Nachricht..."
    create_pipeline_task "$input"
}

# Chat-Loop
chat_loop() {
    local input

    while true; do
        echo -e -n "${GREEN}${BOLD}Du >${NC} "
        read -r input

        process_input "$input"
    done
}

# Main
main() {
    show_banner

    # Prüfe ob jq verfügbar ist
    if ! command -v jq &> /dev/null; then
        print_message "system" "❌ jq ist nicht installiert. Bitte installiere jq."
        exit 1
    fi

    # Starte Chat
    log "Chat started"
    chat_loop
}

# CLI Interface
case "${1:-}" in
    "status")
        show_status
        ;;
    "tasks")
        show_tasks
        ;;
    "history")
        show_history
        ;;
    "pipeline")
        shift
        create_pipeline_task "$@"
        ;;
    "single")
        shift
        create_single_task "$@"
        ;;
    *)
        main
        ;;
esac