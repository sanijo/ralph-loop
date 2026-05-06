#!/bin/sh
set -eu

usage() {
  cat <<'USAGE'
Usage: scripts/install.sh [--dry-run] [--force] <target-git-repo>

Install the Ralph Loop template into a target git repository.

Options:
  --dry-run   Print planned changes without writing files.
  --force     Overwrite conflicting managed files.
USAGE
}

dry_run=0
force=0
target=

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      dry_run=1
      ;;
    --force)
      force=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [ -n "$target" ]; then
        echo "Only one target path may be supplied" >&2
        usage >&2
        exit 2
      fi
      target=$1
      ;;
  esac
  shift
done

if [ -z "$target" ]; then
  echo "Target git repository path is required" >&2
  usage >&2
  exit 2
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
template_dir=$repo_root/template

if ! git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Target is not a git worktree: $target" >&2
  exit 1
fi

target_root=$(git -C "$target" rev-parse --show-toplevel)

say() {
  if [ "$dry_run" -eq 1 ]; then
    printf 'DRY-RUN: %s\n' "$1"
  else
    printf '%s\n' "$1"
  fi
}

install_file() {
  src=$1
  dest=$2
  rel=${dest#"$target_root"/}

  if [ -f "$dest" ]; then
    if cmp -s "$src" "$dest"; then
      say "skip identical $rel"
      return 0
    fi

    if [ "$force" -ne 1 ]; then
      echo "Refusing to overwrite conflicting managed file: $rel" >&2
      echo "Rerun with --force to replace it." >&2
      exit 1
    fi

    say "overwrite $rel"
  else
    say "create $rel"
  fi

  if [ "$dry_run" -ne 1 ]; then
    mkdir -p "$(dirname -- "$dest")"
    cp "$src" "$dest"
  fi
}

find "$template_dir" -type f | sort | while IFS= read -r src; do
  rel=${src#"$template_dir"/}
  install_file "$src" "$target_root/$rel"
done

gitignore=$target_root/.gitignore
gitignore_block='### Ralph Loop managed block
.ralph/.env
.ralph/logs/
.ralph/tmp/
.ralph/cache/
### End Ralph Loop managed block'

if [ -f "$gitignore" ] && grep -Fq '### Ralph Loop managed block' "$gitignore"; then
  say "skip existing .gitignore Ralph block"
else
  say "append .gitignore Ralph block"
  if [ "$dry_run" -ne 1 ]; then
    if [ -f "$gitignore" ] && [ -s "$gitignore" ]; then
      printf '\n%s\n' "$gitignore_block" >>"$gitignore"
    else
      printf '%s\n' "$gitignore_block" >>"$gitignore"
    fi
  fi
fi

say "Ralph Loop template installation complete for $target_root"
