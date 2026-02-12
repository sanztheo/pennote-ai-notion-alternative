#!/bin/bash
# ============================================================================
# ORCHESTRATOR.SH - Multi-Agent Development Loop for PenNote
# ============================================================================
# Inspired by Peter Steinberger's agentic workflow (OpenClaw)
#
# AGENTS:
#   1. CLAUDE  - Developpeur principal (recoit les taches, code)
#   2. GEMINI  - Reviewer (analyse le code, ecrit critiques dans REVIEW.md)
#   3. CODEX   - Second reviewer / Assistant (peut aider Claude a corriger)
#
# ARCHITECTURE:
# 1. watchexec surveille les fichiers source (pen-frontend/src, pen-backend/src)
# 2. Quand un fichier change, Gemini analyse et ecrit dans REVIEW.md
# 3. Si REVIEW.md contient des erreurs, Claude/Codex corrigent automatiquement
# 4. La boucle continue jusqu'a ce que REVIEW.md contienne "OK"
#
# USAGE:
#   ./orchestrator.sh          # Lance l'orchestration complete
#   ./orchestrator.sh --manual # Affiche les commandes pour lancement manuel
#   ./orchestrator.sh --4panes # Affiche les commandes pour 4 volets (avec Codex)
# ============================================================================

set -e

PROJECT_ROOT="/Users/sanz/Desktop/Pennote"
REVIEW_FILE="$PROJECT_ROOT/REVIEW.md"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
echo_success() { echo -e "${GREEN}[OK]${NC} $1"; }
echo_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check dependencies
check_deps() {
    echo_info "Verification des dependances..."

    if ! command -v watchexec &> /dev/null; then
        echo_error "watchexec non installe. Installez avec: brew install watchexec"
        exit 1
    fi

    if ! command -v gemini &> /dev/null; then
        echo_error "gemini CLI non installe."
        exit 1
    fi

    if ! command -v claude &> /dev/null; then
        echo_error "claude CLI non installe."
        exit 1
    fi

    echo_success "Toutes les dependances sont installees"
}

# Show manual commands for Warp split panes (3 panes)
show_manual() {
    echo ""
    echo "=============================================="
    echo "  COMMANDES POUR LANCEMENT MANUEL (3 volets)"
    echo "=============================================="
    echo ""
    echo "Ouvrez 3 volets dans Warp (Cmd+D) et executez:"
    echo ""
    echo "--- VOLET 1: Claude (Agent Principal) ---"
    echo "cd $PROJECT_ROOT && claude"
    echo ""
    echo "--- VOLET 2: Gemini (Code Reviewer avec regles) ---"
    echo "cd $PROJECT_ROOT && watchexec -w pen-frontend/src -w pen-backend/src -e ts,tsx,js,jsx -- bash -c 'RULES=\$(cat .agent-rules.md) && gemini -p \"REGLES A APPLIQUER:\n\$RULES\n\n---\n\nAnalyse les fichiers TypeScript modifies selon ces regles. Ecris les erreurs dans REVIEW.md avec le format specifie. Si tout OK, ecris juste OK.\"'"
    echo ""
    echo "--- VOLET 3: Claude Auto-Fix ---"
    echo "cd $PROJECT_ROOT && watchexec -w REVIEW.md -- bash -c 'if ! grep -q \"^OK\" REVIEW.md 2>/dev/null; then cc -p \"Lis REVIEW.md et .agent-rules.md, puis applique les corrections dans le code source.\"; fi'"
    echo ""
    echo "=============================================="
}

# Show manual commands for 4 panes (with Codex)
show_4panes() {
    echo ""
    echo "=============================================="
    echo "  COMMANDES POUR 4 VOLETS (avec Codex)"
    echo "=============================================="
    echo ""
    echo "Ouvrez 4 volets dans Warp (Cmd+D + Cmd+Shift+D) et executez:"
    echo ""
    echo "--- VOLET 1: Claude (Agent Principal) ---"
    echo "cd $PROJECT_ROOT && claude"
    echo ""
    echo "--- VOLET 2: Gemini (Code Reviewer avec regles) ---"
    echo "cd $PROJECT_ROOT && watchexec -w pen-frontend/src -w pen-backend/src -e ts,tsx,js,jsx -- bash -c 'RULES=\$(cat .agent-rules.md) && gemini -p \"REGLES:\n\$RULES\n\n---\n\nAnalyse le code modifie. Ecris les erreurs dans REVIEW.md ou OK.\"'"
    echo ""
    echo "--- VOLET 3: Codex (Assistant avec regles) ---"
    echo "cd $PROJECT_ROOT && codex"
    echo "# Puis donne-lui: 'Lis .agent-rules.md et aide a corriger le code'"
    echo ""
    echo "--- VOLET 4: Auto-Fix Loop ---"
    echo "cd $PROJECT_ROOT && watchexec -w REVIEW.md -- bash -c 'if ! grep -q \"^OK\" REVIEW.md 2>/dev/null; then cc -p \"Lis REVIEW.md et .agent-rules.md, puis corrige le code.\"; fi'"
    echo ""
    echo "=============================================="
    echo ""
    echo "FICHIERS DE REGLES:"
    echo "  .agent-rules.md  - Regles condensees pour tous les agents"
    echo "  CLAUDE.md        - Instructions completes du projet"
    echo ""
    echo "TIP: Au demarrage de Codex, tape:"
    echo "  'Lis .agent-rules.md et utilise ces regles pour m'aider'"
    echo ""
}

# Main orchestration loop
run_orchestration() {
    echo ""
    echo "=============================================="
    echo "  PENNOTE MULTI-AGENT ORCHESTRATOR"
    echo "=============================================="
    echo ""
    echo_info "Project: $PROJECT_ROOT"
    echo_info "Review file: $REVIEW_FILE"
    echo ""

    # Initialize REVIEW.md
    echo "# REVIEW.md - En attente..." > "$REVIEW_FILE"
    echo_success "REVIEW.md initialise"

    echo ""
    echo_warning "L'orchestration automatique complete n'est pas encore implementee."
    echo_warning "Utilisez le mode manuel pour l'instant:"
    echo ""
    show_manual
}

# Parse arguments
case "${1:-}" in
    --manual|-m)
        show_manual
        ;;
    --4panes|-4)
        show_4panes
        ;;
    --help|-h)
        echo "Usage: ./orchestrator.sh [--manual|--4panes|--help]"
        echo ""
        echo "Options:"
        echo "  --manual, -m    Affiche les commandes pour 3 volets"
        echo "  --4panes, -4    Affiche les commandes pour 4 volets (avec Codex)"
        echo "  --help, -h      Affiche cette aide"
        ;;
    *)
        check_deps
        run_orchestration
        ;;
esac
