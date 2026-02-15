#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
backup_dir="${1:-$repo_root/backups}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
repo_name="$(basename "$repo_root")"

mkdir -p "$backup_dir"

bundle_path="$backup_dir/${repo_name}_${timestamp}.bundle"
tar_path="$backup_dir/${repo_name}_${timestamp}.tar.gz"
sha_path="$backup_dir/${repo_name}_${timestamp}.sha256"

# If backup_dir is inside repo_root, exclude it from the tarball to avoid
# self-inclusion warnings (archive changes while being written).
tar_excludes=(--exclude='./.git')
case "$backup_dir" in
  "$repo_root"/*)
    rel_backup_dir="${backup_dir#"$repo_root"/}"
    tar_excludes+=(--exclude="./${rel_backup_dir}")
    ;;
esac

(
  cd "$repo_root"
  git bundle create "$bundle_path" --all
  tar "${tar_excludes[@]}" -czf "$tar_path" .
)

sha256sum "$bundle_path" "$tar_path" > "$sha_path"

cat <<MSG
Full backup created:
- Git history bundle: $bundle_path
- Working tree archive: $tar_path
- SHA-256 checksums: $sha_path

To restore from the bundle:
  git clone "$bundle_path" restored_${repo_name}

To restore files from the tarball:
  tar -xzf "$tar_path"
MSG
