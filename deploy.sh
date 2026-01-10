#!/bin/bash

echo "🔧 Building Hugo site..."
hugo --minify

cd public || exit

echo "📦 Deploying to GitHub Pages..."

git add .
git commit -m "auto deploy $(date '+%Y-%m-%d %H:%M:%S')" || echo "No changes to commit"
git push origin main

echo "✅ Deploy selesai!"
