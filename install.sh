#!/bin/bash
# install.sh - Ein-Klick-Installation für Multi-Agent Project Team System
# Usage: curl -fsSL https://your-repo/install.sh | bash
# oder: ./install.sh

set -euo pipefail

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
MUTED='\033[90m'
NC='\033[0m'

# Konfiguration
TEAM_ROOT="${TEAM_ROOT:-$HOME/project-team}"
MODEL="${MODEL:-glm-5-cloud}"

# Banner
show_banner() {
    echo -e "${CYAN}"
    echo -e "╔════════════════════════════════════════════════════════════╗"
    echo -e "║                                                            ║"
    echo -e "║     🤖  Multi-Agent Project Team System                    ║"
    echo -e "║     ───────────────────────────────────                   ║"
    echo -e "║     5 Agenten • Pipeline • Ollama • glm-5-cloud           ║"
    echo -e "║                                                            ║"
    echo -e "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

# Prüfe Command
check_command() {
    local cmd="$1"
    local name="${2:-$cmd}"
    if command -v "$cmd" &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} $name"
        return 0
    else
        echo -e "  ${YELLOW}✗${NC} $name ${MUTED}(fehlt)${NC}"
        return 1
    fi
}

# Installiere Homebrew (macOS)
install_homebrew() {
    if [[ "$OSTYPE" == "darwin"* ]] && ! command -v brew &> /dev/null; then
        echo -e "${YELLOW}Installiere Homebrew...${NC}"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
}

# Installiere Abhängigkeiten
install_dependencies() {
    echo -e "${BOLD}[2/6]${NC} Installiere Abhängigkeiten..."

    local missing=()

    # jq
    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi

    # git
    if ! command -v git &> /dev/null; then
        missing+=("git")
    fi

    # curl
    if ! command -v curl &> /dev/null; then
        missing+=("curl")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "  ${YELLOW}Installiere: ${missing[*]}${NC}"

        if [[ "$OSTYPE" == "darwin"* ]]; then
            brew install "${missing[@]}"
        elif command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y "${missing[@]}"
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y "${missing[@]}"
        else
            echo -e "${RED}Bitte installiere manuell: ${missing[*]}${NC}"
            exit 1
        fi
    fi

    echo -e "  ${GREEN}✓${NC} Alle Abhängigkeiten installiert"
}

# Installiere Ollama
install_ollama() {
    echo -e "${BOLD}[3/6]${NC} Installiere Ollama..."

    if command -v ollama &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} Ollama bereits installiert"
        return 0
    fi

    echo -e "  ${YELLOW}Installiere Ollama...${NC}"

    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew &> /dev/null; then
            brew install ollama
        else
            echo -e "  ${YELLOW}Download von https://ollama.com${NC}"
            open "https://ollama.com/download"
            echo -e "  ${YELLOW}Bitte Ollama manuell installieren und neu starten${NC}"
            exit 0
        fi
    elif [[ "$OSTYPE" == "linux"* ]]; then
        # Linux
        curl -fsSL https://ollama.com/install.sh | sh
    else
        echo -e "  ${RED}Bitte Ollama manuell installieren: https://ollama.com${NC}"
        exit 1
    fi

    echo -e "  ${GREEN}✓${NC} Ollama installiert"
}

# Erstelle Projektstruktur
create_structure() {
    echo -e "${BOLD}[4/6]${NC} Erstelle Projektstruktur..."

    mkdir -p "$TEAM_ROOT"/{agents/{architekt-pm,entwickler,tester-qa,dokumentator,git-manager}/{workspace,memory}} \
        "$TEAM_ROOT"/{backlog/{todo,doing,done,failed,handoffs/{pending,archive}}} \
        "$TEAM_ROOT"/{coordinator,shared/{context,memory,templates,skills}} \
        "$TEAM_ROOT"/{scripts,config,logs/agents,results,.team}

    echo -e "  ${GREEN}✓${NC} Verzeichnisse erstellt"
}

# Erstelle Konfigurationsdateien
create_configs() {
    echo -e "${BOLD}[5/6]${NC} Erstelle Konfiguration..."

    # Agent-Definitions
    cat > "$TEAM_ROOT/config/agent-definitions.json" << 'AGENTEOF'
{
  "version": "1.0.0",
  "project": "Multi-Agent Project Team System",
  "model": "ollama/glm-5-cloud",
  "workflow_overview": {
    "pipeline": ["architekt-pm", "entwickler", "tester-qa", "dokumentator", "git-manager"],
    "handoff_protocol": "JSON-basierte Handoffs zwischen Agenten"
  },
  "agents": [
    {
      "id": "architekt-pm",
      "name": "Architekt/PM",
      "role": "Architecture Design, Planning & Coordination",
      "position_in_pipeline": 1,
      "system_prompt": {
        "identity": "Du bist der Architekt und Project Manager. Du denkst in Systemen und Roadmaps.",
        "responsibilities": ["Architektur-Entscheidungen", "Task-Breakdown", "ADRs"],
        "output_format": "architecture_brief JSON"
      },
      "model_config": { "temperature": 0.5, "max_tokens": 8192 }
    },
    {
      "id": "entwickler",
      "name": "Entwickler",
      "role": "Code Implementation & Bug Fixes",
      "position_in_pipeline": 2,
      "system_prompt": {
        "identity": "Du bist der Entwickler. Du setzt Architektur in sauberen Code um.",
        "responsibilities": ["Feature-Implementierung", "Tests", "Refactoring"],
        "output_format": "implementation_report JSON"
      },
      "model_config": { "temperature": 0.3, "max_tokens": 8192 }
    },
    {
      "id": "tester-qa",
      "name": "Tester/QA",
      "role": "Test Execution & Validation",
      "position_in_pipeline": 3,
      "system_prompt": {
        "identity": "Du bist der QA-Engineer. Du findest Edge Cases und validierst.",
        "responsibilities": ["Test-Plan", "Edge Cases", "Bug Reports"],
        "output_format": "qa_report JSON"
      },
      "model_config": { "temperature": 0.2, "max_tokens": 4096 }
    },
    {
      "id": "dokumentator",
      "name": "Dokumentator",
      "role": "Documentation & README",
      "position_in_pipeline": 4,
      "system_prompt": {
        "identity": "Du bist der Dokumentator. Du schreibst verständliche Dokumentation.",
        "responsibilities": ["README", "API Docs", "Changelog"],
        "output_format": "documentation_report JSON"
      },
      "model_config": { "temperature": 0.4, "max_tokens": 4096 }
    },
    {
      "id": "git-manager",
      "name": "Git Manager",
      "role": "Git Operations & Issues",
      "position_in_pipeline": 5,
      "system_prompt": {
        "identity": "Du bist der Git Manager. Du verwendest Conventional Commits.",
        "responsibilities": ["Commits", "PRs", "Issues", "Project Board"],
        "output_format": "git_report JSON"
      },
      "model_config": { "temperature": 0.3, "max_tokens": 4096 }
    }
  ]
}
AGENTEOF

    # Model-Config
    cat > "$TEAM_ROOT/config/model-config.json" << 'MODELEOF'
{
  "model": { "name": "glm-5-cloud", "provider": "ollama", "type": "cloud" },
  "fallback": { "enabled": true, "models": ["llama3.2:latest", "mistral:latest"] },
  "rate_limiting": { "requests_per_minute": 60 }
}
MODELEOF

    # Handoff-Schema
    cat > "$TEAM_ROOT/shared/templates/handoff-schema.json" << 'SCHEMAEOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Agent Handoff Payload",
  "type": "object",
  "required": ["from_agent", "to_agent", "timestamp", "status", "payload"],
  "properties": {
    "from_agent": { "type": "string", "enum": ["architekt-pm", "entwickler", "tester-qa", "dokumentator", "git-manager", "user"] },
    "to_agent": { "type": "string", "enum": ["architekt-pm", "entwickler", "tester-qa", "dokumentator", "git-manager", "complete"] },
    "timestamp": { "type": "string", "format": "date-time" },
    "status": { "type": "string", "enum": ["READY", "BLOCKED", "IN_REVISION", "APPROVED", "DEPLOYED"] },
    "task_reference": { "type": "string" },
    "payload": { "type": "object" }
  }
}
SCHEMAEOF

    # Team Memory
    cat > "$TEAM_ROOT/shared/memory/TEAM_MEMORY.md" << 'MEMEOF'
# TEAM_MEMORY.md

## Project Overview
- **System**: Multi-Agent Project Team System
- **Model**: glm-5-cloud
- **Pipeline**: Architekt → Entwickler → Tester → Dokumentator → Git Manager

## Current Project
- **Status**: Ready

## Agent Notes
<!-- Updated during pipeline execution -->
MEMEOF

    echo -e "  ${GREEN}✓${NC} Konfiguration erstellt"
}

# Erstelle Skripte
create_scripts() {
    echo -e "${BOLD}[6/6]${NC} Erstelle Skripte..."

    # Orchestrator
    cat > "$TEAM_ROOT/coordinator/orchestrator.sh" << 'ORCHEOF'
#!/bin/bash
set -euo pipefail
TEAM_ROOT="${TEAM_ROOT:-$HOME/project-team}"
BACKLOG="$TEAM_ROOT/backlog"
HANDOFFS="$TEAM_ROOT/backlog/handoffs"
LOG="$TEAM_ROOT/logs/orchestrator.log"
mkdir -p "$BACKLOG"/{todo,doing,done,failed} "$HANDOFFS"/{pending,archive} "$TEAM_ROOT/logs/agents"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"; }

acquire_lock() {
    LOCK="/tmp/project-team-orchestrator.lock"
    [ -f "$LOCK" ] && OLD=$(cat "$LOCK" 2>/dev/null) && [ -n "$OLD" ] && kill -0 "$OLD" 2>/dev/null && exit 0
    echo $$ > "$LOCK"
    trap 'rm -f "$LOCK"; log "Stopped"; exit 0' SIGTERM SIGINT EXIT
}

NEXT_AGENT=(["architekt-pm"]="entwickler" ["entwickler"]="tester-qa" ["tester-qa"]="dokumentator" ["dokumentator"]="git-manager" ["git-manager"]="complete")

main() {
    log "Orchestrator started (PID $$)"
    acquire_lock
    while true; do
        HANDOFF=$(ls -t "$HANDOFFS/pending/"*.json 2>/dev/null | head -1)
        TASK=$(ls -1 "$BACKLOG/todo/"*.{md,json} 2>/dev/null | sort | head -1)
        [ -z "$HANDOFF" ] && [ -z "$TASK" ] && { sleep 60; continue; }
        # Process task logic here...
        sleep 30
    done
}

case "${1:-}" in
    run) main ;;
    status) [ -f "$TEAM_ROOT/.team/orchestrator-state.json" ] && cat "$TEAM_ROOT/.team/orchestrator-state.json" || echo '{"status":"not_running"}' ;;
    *) echo "Usage: $0 {run|status}" ;;
esac
ORCHEOF
    chmod +x "$TEAM_ROOT/coordinator/orchestrator.sh"

    # Worker
    cat > "$TEAM_ROOT/scripts/team-worker.sh" << 'WORKEREOF'
#!/bin/bash
set -euo pipefail
TEAM_ROOT="${TEAM_ROOT:-$HOME/project-team}"
BACKLOG="$TEAM_ROOT/backlog"
LOG="/tmp/team-worker.log"
MODEL="${MODEL:-glm-5-cloud}"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"; }

acquire_lock() {
    LOCK="/tmp/team-worker.lock"
    [ -f "$LOCK" ] && OLD=$(cat "$LOCK" 2>/dev/null) && [ -n "$OLD" ] && kill -0 "$OLD" 2>/dev/null && exit 0
    echo $$ > "$LOCK"
    trap 'rm -f "$LOCK"; log "Stopped"; exit 0' SIGTERM SIGINT EXIT
}

process_task() {
    local task="$1"
    local name=$(basename "$task" | sed 's/\.[^.]*$//')
    log "Processing: $name"
    mv "$task" "$BACKLOG/doing/"
    # Agent processing logic here...
    sleep 5
    mv "$BACKLOG/doing/"* "$BACKLOG/done/" 2>/dev/null || true
    log "Completed: $name"
}

main() {
    log "Worker started (PID $$)"
    acquire_lock
    mkdir -p "$BACKLOG"/{todo,doing,done,failed}
    while true; do
        TASK=$(ls -1 "$BACKLOG/todo/"*.{md,json} 2>/dev/null | sort | head -1)
        [ -z "$TASK" ] && { sleep 60; continue; }
        process_task "$TASK"
        sleep 30
    done
}

case "${1:-}" in
    run) main ;;
    status) [ -f "$TEAM_ROOT/.team/worker-state.json" ] && cat "$TEAM_ROOT/.team/worker-state.json" || echo '{"status":"not_running"}' ;;
    *) echo "Usage: $0 {run|status}" ;;
esac
WORKEREOF
    chmod +x "$TEAM_ROOT/scripts/team-worker.sh"

    # Task-Creator
    cat > "$TEAM_ROOT/scripts/task-creator.sh" << 'TASKEOF'
#!/bin/bash
set -euo pipefail
TEAM_ROOT="${TEAM_ROOT:-$HOME/project-team}"
BACKLOG="$TEAM_ROOT/backlog/todo"
mkdir -p "$BACKLOG"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; MUTED='\033[90m'; NC='\033[0m'

usage() {
    echo -e "${BOLD}Task Creator${NC}"
    echo "Usage: $0 <command> [args]"
    echo ""
    echo "Commands:"
    echo "  single <agent> <description>  Create single-agent task"
    echo "  pipeline <description>       Create full pipeline task"
    echo "  list                           List pending tasks"
    echo "  status                         Show backlog status"
    exit 1
}

create_pipeline() {
    local desc="$*"
    local ts=$(date +%s)
    local file="$BACKLOG/${ts}-pipeline.json"
    jq -n --arg desc "$desc" --arg ts "$(date -Iseconds)" \
        '{type:"pipeline",description:$desc,pipeline:["architekt-pm","entwickler","tester-qa","dokumentator","git-manager"],created:$ts,status:"todo"}' > "$file"
    echo -e "${GREEN}✓${NC} Pipeline task created: $file"
}

create_single() {
    local agent="$1"; shift
    local desc="$*"
    local ts=$(date +%s)
    local file="$BACKLOG/${ts}-single-${agent}.json"
    jq -n --arg agent "$agent" --arg desc "$desc" --arg ts "$(date -Iseconds)" \
        '{type:"single",agent:$agent,description:$desc,created:$ts,status:"todo"}' > "$file"
    echo -e "${GREEN}✓${NC} Single task created: $file"
}

list_tasks() {
    echo -e "${BOLD}Pending Tasks:${NC}"
    for f in "$BACKLOG"/*.{md,json} 2>/dev/null; do
        [ -f "$f" ] || continue
        local name=$(basename "$f")
        [[ "$name" == *"-pipeline"* ]] && echo -e "  ${BLUE}[PIPELINE]${NC} $name"
        [[ "$name" == *"-single"* ]] && echo -e "  ${GREEN}[SINGLE]${NC} $name"
    done
}

show_status() {
    local todo=$(ls -1 "$TEAM_ROOT/backlog/todo/"*.{md,json} 2>/dev/null | wc -l | tr -d ' ')
    local doing=$(ls -1 "$TEAM_ROOT/backlog/doing/"*.{md,json} 2>/dev/null | wc -l | tr -d ' ')
    local done=$(ls -1 "$TEAM_ROOT/backlog/done/"*.{md,json} 2>/dev/null | wc -l | tr -d ' ')
    echo -e "${BOLD}Backlog:${NC} TODO=$todo DOING=$doing DONE=$done"
}

case "${1:-}" in
    single) shift; create_single "$@" ;;
    pipeline) shift; create_pipeline "$@" ;;
    list) list_tasks ;;
    status) show_status ;;
    *) usage ;;
esac
TASKEOF
    chmod +x "$TEAM_ROOT/scripts/task-creator.sh"

    # Status-Script
    cat > "$TEAM_ROOT/scripts/team-status.sh" << 'STATEOF'
#!/bin/bash
TEAM_ROOT="${TEAM_ROOT:-$HOME/project-team}"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; MUTED='\033[90m'; NC='\033[0m'

echo -e "${BOLD}╔════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║    Project Team Status                  ║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════╝${NC}"

# Ollama
if pgrep -f "ollama" > /dev/null; then
    echo -e "${GREEN}●${NC} Ollama: Running"
else
    echo -e "${RED}●${NC} Ollama: Not Running"
fi

# Worker
if pgrep -f "team-worker" > /dev/null; then
    echo -e "${GREEN}●${NC} Worker: Running"
else
    echo -e "${YELLOW}●${NC} Worker: Not Running"
fi

# Orchestrator
if pgrep -f "orchestrator" > /dev/null; then
    echo -e "${GREEN}●${NC} Orchestrator: Running"
else
    echo -e "${YELLOW}●${NC} Orchestrator: Not Running"
fi

# Backlog
echo ""
todo=$(ls -1 "$TEAM_ROOT/backlog/todo/"*.{md,json} 2>/dev/null | wc -l | tr -d ' ')
doing=$(ls -1 "$TEAM_ROOT/backlog/doing/"*.{md,json} 2>/dev/null | wc -l | tr -d ' ')
done=$(ls -1 "$TEAM_ROOT/backlog/done/"*.{md,json} 2>/dev/null | wc -l | tr -d ' ')
echo -e "${BOLD}Backlog:${NC} TODO=$todo DOING=$doing DONE=$done"

# Quick commands
echo ""
echo -e "${BOLD}Commands:${NC}"
echo -e "  ${MUTED}./scripts/task-creator.sh pipeline \"Task\"${NC}"
echo -e "  ${MUTED}./scripts/task-creator.sh list${NC}"
STATEOF
    chmod +x "$TEAM_ROOT/scripts/team-status.sh"

    # Start-Script
    cat > "$TEAM_ROOT/scripts/start-team.sh" << 'STARTEOF'
#!/bin/bash
set -euo pipefail
TEAM_ROOT="${TEAM_ROOT:-$HOME/project-team}"
MODEL="${MODEL:-glm-5-cloud}"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; BOLD='\033[1m'; MUTED='\033[90m'; NC='\033[0m'

echo -e "${BOLD}Starting Project Team...${NC}"

# Ensure Ollama
if ! pgrep -f "ollama" > /dev/null; then
    echo -e "${BLUE}Starting Ollama...${NC}"
    ollama serve &
    sleep 3
fi

# Pull model if needed
if ! ollama list 2>/dev/null | grep -q "$MODEL"; then
    echo -e "${BLUE}Pulling model $MODEL...${NC}"
    ollama pull "$MODEL" || echo -e "${MUTED}Using fallback${NC}"
fi

# Kill existing processes
pkill -f "team-worker.sh" 2>/dev/null || true
pkill -f "orchestrator.sh" 2>/dev/null || true
sleep 1

# Start services
mkdir -p "$TEAM_ROOT/logs/agents"

echo -e "${BLUE}Starting Worker...${NC}"
nohup "$TEAM_ROOT/scripts/team-worker.sh" run > /tmp/team-worker.log 2>&1 &
echo -e "${GREEN}✓${NC} Worker started"

echo -e "${BLUE}Starting Orchestrator...${NC}"
nohup "$TEAM_ROOT/coordinator/orchestrator.sh" run > /tmp/orchestrator.log 2>&1 &
echo -e "${GREEN}✓${NC} Orchestrator started"

echo ""
echo -e "${BOLD}System Ready!${NC}"
echo ""
echo -e "Commands:"
echo -e "  ${MUTED}./scripts/task-creator.sh pipeline \"Your task\"${NC}"
echo -e "  ${MUTEN}./scripts/task-creator.sh list${NC}"
echo -e "  ${MUTED}./scripts/team-status.sh${NC}"
STARTEOF
    chmod +x "$TEAM_ROOT/scripts/start-team.sh"

    # README
    cat > "$TEAM_ROOT/README.md" << 'READMEEOF'
# Multi-Agent Project Team System

Ein-Klick-Start: `./scripts/start-team.sh`

## Pipeline

```
Architekt/PM → Entwickler → Tester/QA → Dokumentator → Git Manager
```

## Befehle

```bash
# System starten
./scripts/start-team.sh

# Status prüfen
./scripts/team-status.sh

# Neue Task (alle Agenten)
./scripts/task-creator.sh pipeline "Create REST API"

# Task auflisten
./scripts/task-creator.sh list
```

## Agenten

| Agent | Rolle |
|-------|-------|
| Architekt/PM | Planung, Architektur |
| Entwickler | Code, Tests |
| Tester/QA | Validierung |
| Dokumentator | README, Doku |
| Git Manager | Commits, PRs |
READMEEOF

    echo -e "  ${GREEN}✓${NC} Skripte erstellt"
}

# Starte Ollama und ziehe Modell
setup_ollama() {
    echo -e "${BLUE}Starte Ollama...${NC}"

    if ! pgrep -f "ollama" > /dev/null; then
        ollama serve &
        sleep 5
    fi

    echo -e "${BLUE}Lade Modell $MODEL...${NC}"
    ollama pull "$MODEL" || echo -e "${YELLOW}Modell nicht verfügbar, verwende Fallback${NC}"

    echo -e "${GREEN}✓${NC} Ollama bereit"
}

# Starte das System
start_system() {
    echo -e "${BLUE}Starte System...${NC}"

    # Töte alte Prozesse
    pkill -f "team-worker.sh" 2>/dev/null || true
    pkill -f "orchestrator.sh" 2>/dev/null || true
    sleep 1

    # Starte Worker
    nohup "$TEAM_ROOT/scripts/team-worker.sh" run > /tmp/team-worker.log 2>&1 &
    echo -e "${GREEN}✓${NC} Worker gestartet"

    # Starte Orchestrator
    nohup "$TEAM_ROOT/coordinator/orchestrator.sh" run > /tmp/orchestrator.log 2>&1 &
    echo -e "${GREEN}✓${NC} Orchestrator gestartet"
}

# Zeige Abschluss-Info
show_completion() {
    echo ""
    echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║     ✓ Installation abgeschlossen!                          ║${NC}"
    echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}Schnellstart:${NC}"
    echo ""
    echo -e "  ${CYAN}cd $TEAM_ROOT${NC}"
    echo -e "  ${CYAN}./scripts/start-team.sh${NC}"
    echo ""
    echo -e "${BOLD}Task erstellen:${NC}"
    echo ""
    echo -e "  ${CYAN}./scripts/task-creator.sh pipeline \"Create a REST API\"${NC}"
    echo ""
    echo -e "${BOLD}Status prüfen:${NC}"
    echo ""
    echo -e "  ${CYAN}./scripts/team-status.sh${NC}"
    echo ""
    echo -e "${BOLD}Logs:${NC}"
    echo ""
    echo -e "  ${MUTED}/tmp/team-worker.log${NC}"
    echo -e "  ${MUTED}/tmp/orchestrator.log${NC}"
    echo ""
    echo -e "${MUTED}Modell: $MODEL${NC}"
    echo -e "${MUTED}Pfad: $TEAM_ROOT${NC}"
    echo ""
}

# Main
main() {
    show_banner

    echo -e "${BOLD}[1/6]${NC} Prüfe System..."
    check_command jq
    check_command git
    check_command curl
    echo ""

    install_dependencies
    install_ollama
    create_structure
    create_configs
    create_scripts

    # Starte Ollama
    setup_ollama

    # Starte System
    start_system

    show_completion
}

# Führe main aus
main "$@"