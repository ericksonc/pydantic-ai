#!/bin/bash
# merge-mobile.sh - Find and merge Mobile's branches

set -e

echo "🔄 Fetching from fork..."
git fetch origin

# Find all claude/* branches from Mobile (exclude main)
MOBILE_BRANCHES=$(git branch -r | grep 'origin/claude/' | grep -v 'HEAD' | sed 's/^ *//' | sed 's/origin\///')

if [ -z "$MOBILE_BRANCHES" ]; then
    echo "❌ No Mobile branches found (looking for origin/claude/*)"
    exit 1
fi

# Show available branches
echo ""
echo "📱 Found Mobile branch(es):"
echo "$MOBILE_BRANCHES" | nl
echo ""

# Count branches
BRANCH_COUNT=$(echo "$MOBILE_BRANCHES" | wc -l | xargs)

if [ "$BRANCH_COUNT" -eq 1 ]; then
    # Only one branch, use it
    MOBILE_BRANCH=$(echo "$MOBILE_BRANCHES" | xargs)
    echo "📱 Using: $MOBILE_BRANCH"
else
    # Multiple branches, use the most recent
    MOBILE_BRANCH=$(echo "$MOBILE_BRANCHES" | tail -1 | xargs)
    echo "📱 Multiple branches found, using most recent: $MOBILE_BRANCH"
fi

echo ""

# Switch to main and update
git checkout main
git pull origin main

# Merge Mobile's branch
echo "🔀 Merging Mobile's changes..."
git merge "origin/$MOBILE_BRANCH" --no-edit

# Push to main
git push origin main
echo "✅ Merged and pushed to main"
echo ""

# Ask about branch cleanup
echo "🧹 Delete remote branch '$MOBILE_BRANCH'? (y/n)"
read -r response
if [ "$response" = "y" ]; then
    git push origin --delete "$MOBILE_BRANCH"
    echo "✅ Remote branch deleted"
else
    echo "ℹ️  Branch kept (you can delete later)"
fi
