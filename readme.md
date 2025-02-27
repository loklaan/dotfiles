# github.com/loklaan/dotfiles

Lochy's dotfiles, managed with [`chezmoi`](https://github.com/twpayne/chezmoi).

Install them with:
```shell
curl -fsSL https://raw.githubusercontent.com/loklaan/dotfiles/main/install.sh > install.sh && \
  BITWARDEN_EMAIL=null@lochlan.io GITHUB_USERNAME="loklaan" bash ./install.sh && \
  rm ./install.sh

# or without the install script
chezmoi init loklaan
```

Personal secrets are stored in [Bitwarden](https://1password.com). The [Bitwarden CLI](https://bitwarden.com/help/cli/) is installed by default. A new login session will need to be run anytime `chezmoi apply` is used:
```shell
bw login # or bw unlock
```
