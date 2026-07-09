# Notedavidrinaldi Hugo Site

[![submit-search-index](https://github.com/notedavidrinaldi/notedavidrinaldi.github.io/actions/workflows/search-indexer.yml/badge.svg)](https://github.com/notedavidrinaldi/notedavidrinaldi.github.io/actions/workflows/search-indexer.yml)

Catatan operasional untuk build, deploy, dan notifikasi indexing mesin pencari.

## Cara cepat jalankan

1. Build + deploy:

```bash
./deploy.sh
```

2. Build + deploy + submit indexer (default aktif):

```bash
./deploy.sh
```

`deploy.sh` akan otomatis menjalankan `program/search-indexer.sh` setelah push ke `main`.

3. Jika ingin skip submit indexer saat deploy:

```bash
RUN_INDEXER=0 ./deploy.sh
```

## search-indexer manual

```bash
bash program/search-indexer.sh https://notedavidrinaldi.github.io https://notedavidrinaldi.github.io/sitemap.xml
```

Opsional:

```bash
bash program/search-indexer.sh --help
bash program/search-indexer.sh --dry-run
```

`--dry-run` hanya simulasi request sitemap/indexing dan **tidak mengirim webhook**.

```bash
bash program/search-indexer.sh --timeout 30 --log-file /tmp/indexer.log https://notedavidrinaldi.github.io
SEARCH_INDEXER_NOTIFY_WEBHOOK=https://hooks.slack.com/services/xxx bash program/search-indexer.sh https://notedavidrinaldi.github.io
bash program/search-indexer.sh --notify-webhook https://hooks.example.com/xxx --notify-webhook-platform discord --timeout 30 https://notedavidrinaldi.github.io
```

### Exit code

- `0`: semua engine sukses
- `1`: sebagian sukses, sebagian belum
- `2`: validasi sitemap gagal / semua request gagal

## Notifikasi webhook

`program/search-indexer.sh` juga bisa kirim notifikasi ke webhook (Slack/Discord/Teams) jika set:

```bash
export SEARCH_INDEXER_NOTIFY_WEBHOOK=https://hooks.example.com/xxx
export SEARCH_INDEXER_NOTIFY_WEBHOOK_PLATFORM=discord
```

Workflow GitHub Actions membaca secret:

- `SEARCH_INDEXER_NOTIFY_WEBHOOK`
- `SEARCH_INDEXER_NOTIFY_WEBHOOK_PLATFORM` (opsional: `auto`, `slack`, `discord`, `teams`)

## GitHub Actions

Workflow otomatis ada di:

- `.github/workflows/search-indexer.yml`

Terpicu pada:

- `push` ke branch `main`
- `workflow_dispatch`

Saat `workflow_dispatch`, bisa set input:

- `webhook_platform` (`auto`, `slack`, `discord`, `teams`) — default `auto`

Workflow menjalankan:

```bash
bash program/search-indexer.sh --timeout 30 --engines google,bing https://notedavidrinaldi.github.io https://notedavidrinaldi.github.io/sitemap.xml
```

## Catatan

- Jika endpoint mesin pencari merespons kode yang bukan sukses, exit code bisa `1` atau `2`.
- Untuk referensi penggunaan di halaman web, lihat:
  - `program/index.html` -> section "Program Referensi Index Search Engine".

## Checklist validasi cepat

Setelah deploy/trigger workflow, lakukan verifikasi berikut:

- [ ] Workflow `submit-search-index` muncul dan statusnya sesuai (green untuk sukses/non-total-fail, red jika `exit=2`).
- [ ] Log step **Kirim sinyal indexing sitemap** menampilkan `exit_code=<0|1|2>`.
- [ ] Jika `exit_code=2`, step **Alert jika gagal total** dieksekusi dan ada notifikasi yang masuk.
- [ ] Jika `exit_code=1`, script menampilkan status sukses parsial (tanpa failing job).
- [ ] Jika test dengan `--dry-run`, pastikan tidak ada webhook yang terkirim (lihat log: `Mode DRY-RUN: skip notifikasi webhook.`).
