#!/bin/bash

set -e

echo "🔧 Building Hugo site..."
hugo --minify

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
INDEXER_SCRIPT="$PROJECT_ROOT/program/search-indexer.sh"
SITE_URL="https://notedavidrinaldi.github.io"
SITEMAP_URL="$SITE_URL/sitemap.xml"
INDEXER_TIMEOUT="30"
RUN_INDEXER="${RUN_INDEXER:-1}"

cd public || exit

echo "📦 Deploying to GitHub Pages..."

git add .
git commit -m "auto deploy $(date '+%Y-%m-%d %H:%M:%S')" || echo "No changes to commit"
git push origin main

if [[ "$RUN_INDEXER" == "1" || "$RUN_INDEXER" == "true" ]]; then
  if [[ -x "$INDEXER_SCRIPT" ]]; then
    echo "🔔 Triggering search index ping (non-blocking)"
    bash "$INDEXER_SCRIPT" --timeout "$INDEXER_TIMEOUT" --log-file "$PROJECT_ROOT/program/search-indexer-deploy.log" "$SITE_URL" "$SITEMAP_URL" || {
      echo "⚠️  Search index ping keluar dengan status non-nol; deploy tetap dianggap selesai."
    }
  else
    echo "⚠️  script pencarian tidak ditemukan/eksekusi: $INDEXER_SCRIPT"
  fi
else
  echo "ℹ️  RUN_INDEXER=$RUN_INDEXER. Skip submit ke mesin pencari."
fi

echo "✅ Deploy selesai!"
