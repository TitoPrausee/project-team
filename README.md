# Multi-Agent Project Team System

Ein koordiniertes Team aus 5 spezialisierten KI-Agenten für Softwareentwicklung.

## Schnellstart

```bash
# System starten
./scripts/start-team.sh

# Status prüfen
./scripts/team-status.sh

# Neue Task erstellen
./scripts/task-creator.sh pipeline "Create a REST API endpoint"

# Tasks auflisten
./scripts/task-creator.sh list
```

## Agenten-Pipeline

```
Architekt/PM → Entwickler → Tester/QA → Dokumentator → Git Manager
```

| Agent | Rolle | Aufgabe |
|-------|-------|---------|
| **Architekt/PM** | Planung | Architektur, Tasks, ADRs |
| **Entwickler** | Code | Implementierung, Tests |
| **Tester/QA** | Validierung | Tests, Bug Reports |
| **Dokumentator** | Docs | README, API Docs |
| **Git Manager** | Git | Commits, PRs, Issues |

## Task-Typen

```bash
# Single-Agent Task
./scripts/task-creator.sh single entwickler "Fix login bug"

# Full Pipeline (alle 5 Agenten)
./scripts/task-creator.sh pipeline "Add authentication"

# Project Task (Henry-Pattern)
./scripts/task-creator.sh project ~/my-repo "Refactor API"
```

## Verzeichnisstruktur

```
~/project-team/
├── agents/           # Agent-Workspaces
├── backlog/          # Tasks
│   ├── todo/
│   ├── doing/
│   ├── done/
│   └── failed/
├── config/           # Konfiguration
├── coordinator/      # Orchestrator
├── scripts/          # Skripte
├── shared/           # Geteilte Ressourcen
└── logs/             # Logs
```

## Konfiguration

- **Model**: `glm-5-cloud` (Ollama)
- **Max Task Time**: 600s
- **Pipeline Timeout**: 3600s

## Docker

```bash
# Mit Docker starten
docker-compose up -d

# Mit Dashboard
docker-compose --profile dashboard up -d

# Logs
docker-compose logs -f worker
```

## Quellen

- Basis: `github.com/TitoPrausee/openclaw-docker`
- Henry-Pattern: `~/Downloads/Henry-main/`