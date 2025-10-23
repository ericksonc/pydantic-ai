# CLAUDE.md

## Purpose

This fork of Pydantic AI is a **workspace for analyzing and understanding the Pydantic AI codebase and documentation**. Both Claude Code Mobile (iOS) and Claude Code Desktop (Mac) collaborate on this analysis, creating reports and documentation in the `claude/` directory.

**What we do here:**
- Explore and analyze the Pydantic AI codebase
- Document how various components work
- Create guides and explainers for complex features
- Share findings between Mobile and Desktop instances

**What we don't do:**
- Develop or modify Pydantic AI itself (this is a read-only analysis fork)
- Run tests or CI/CD workflows (removed for simplicity)

## Repository Setup

- **Fork**: `ericksonc/pydantic-ai`
- **Upstream**: `pydantic/pydantic-ai` (official repo, for reference only)
- **Working Directory**: `claude/` - all reports and documentation go here
- **No CI/CD**: GitHub Actions workflows have been removed (we only sync markdown files)

## Sync Workflow

### For Claude Code Mobile (iOS)

**Mobile's git restrictions** (Anthropic-imposed):
- Cannot push to `main` directly (HTTP 403 error)
- Must push to session-specific branches under `claude/*`
- Branch names are auto-generated per conversation/session

**What Mobile should do:**
1. **Analyze code** and create reports in `claude/` directory
2. **Commit changes** with descriptive messages
3. **Push to your branch** (whatever Anthropic allows - typically `claude/*`)
4. **Done!** Desktop will merge it

### For Claude Code Desktop (Mac)

**To sync Mobile's analysis reports:**

```bash
./merge-mobile.sh
```

This script will:
- Find all Mobile branches (anything under `origin/claude/*`)
- Merge the most recent one to `main`
- Push to fork
- Optionally delete the Mobile branch (cleanup)

**Alternative - manual process:**
```bash
git fetch origin
git checkout main
git merge origin/claude/[branch-name]
git push origin main
```

## File Organization

```
claude/
├── [various report files].md       # Reports created by either Mobile or Desktop
├── modelmessage/                   # Organized documentation subdirectories
│   └── [related docs].md
└── user/                           # User-specific documentation
    └── [user docs].md
```

## How Analysis & Sync Works

**Analysis Flow:**
- Both Mobile and Desktop Claude analyze the Pydantic AI codebase
- Reports and findings are written to `claude/` directory
- Each instance can build on the other's work

**Sync Flow:**
```
Mobile: Analyzes code → Creates report → Commits & pushes to claude/* branch
                                                ↓
                                GitHub Fork (ericksonc/pydantic-ai)
                                                ↓
Desktop: Runs ./merge-mobile.sh → Merges to main → Can continue analysis
```

## Important Notes

- **Mobile creates branches**: Anthropic restricts Mobile to `claude/*` branches (can't push to `main`)
- **Desktop merges**: Use `./merge-mobile.sh` to consolidate Mobile's work into `main`
- **Conflicts are rare**: Mobile and Desktop typically work on different files
- **If conflicts occur**: Desktop resolves during merge, then pushes
- **Branch cleanup**: Delete Mobile branches after merging (script will prompt)
- **Original CLAUDE.md**: See `CLAUDE-original.md` for Pydantic AI development instructions

## Reference Links

- Fork: https://github.com/ericksonc/pydantic-ai
- Upstream: https://github.com/pydantic/pydantic-ai
- Claude Code: https://claude.com/claude-code
