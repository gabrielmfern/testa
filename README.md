# testa

## Cloning

This repo stores the `vendor/libnode/*` binaries in [Git LFS](https://git-lfs.com).
Without LFS you'll get small pointer files instead of the real libraries, and the
build will fail with `BadMagic`.

1. Install Git LFS: `sudo pacman -S git-lfs` (or your platform's package manager)
2. Enable it once per machine: `git lfs install`
3. Clone as usual: `git clone https://github.com/gabrielmfern/testa.git`

Already cloned before installing LFS? Run `git lfs pull` to fetch the real binaries.
