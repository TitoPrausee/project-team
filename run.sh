#!/bin/bash
# run.sh - Startet das gesamte System mit einem Befehl
# Usage: ./run.sh

cd "$(dirname "$0")"

# Führe Installation aus falls nötig
if [ ! -f "config/agent-definitions.json" ]; then
    echo "Erste Ausführung - führe Installation durch..."
    ./install.sh
fi

# Starte das System
./scripts/start-team.sh