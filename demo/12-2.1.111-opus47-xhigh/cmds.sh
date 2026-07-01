stty cols 92 rows 7 2>/dev/null || true
PS='$ '
step() { printf '%s%s\n' "$PS" "$*"; sleep 1.0; eval "$*" 2>&1 || true; sleep 1.4; }
step "claude --help 2>&1 | grep -iA1 -- '--effort' | head -6"
