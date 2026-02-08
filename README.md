# swap-merge.nvim

Three-way merge for external file changes in Neovim.

When you're editing a file and something else modifies it (an AI agent, another process, a teammate), swap-merge lets you merge both sets of changes instead of choosing one or the other.

## Installation

```lua
-- lazy.nvim
{
  "flamingoosesoftwareinc/swap-merge.nvim",
  opts = {},
}
```

## How it works

1. When you open a file, swap-merge saves a "shadow" copy
2. You make edits (unsaved in buffer)
3. External process modifies the file on disk
4. swap-merge detects the change and offers to merge
5. Uses `git merge-file` for three-way merge: your buffer + shadow (base) + disk
6. On save, shadow updates — ready for the next merge

No git repository required. Shadow files stored in `~/.cache/nvim/swap-merge-shadows/`.

## Keybindings

| Key | Action |
|-----|--------|
| `<leader>bm` | Merge external changes into buffer |
| `<leader>bD` | Open three-way diff view |

## Commands

- `:SwapMerge` — Merge external changes
- `:SwapDiff` — Open three-way diff (yours / base / theirs)

## Configuration

```lua
{
  "flamingoosesoftwareinc/swap-merge.nvim",
  opts = {
    keymap_merge = "<leader>bm",
    keymap_diff = "<leader>bD",
    auto_prompt = true, -- prompt on FileChangedShell
  },
}
```

## Requirements

- Neovim 0.8+
- `git` (for `git merge-file`)
