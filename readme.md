```
╔══════════════════════════════════════════════════════════════════════╗
║                                                                      ║
║       ✨ github.com/loklaan/dotfiles ✨                             ║
║                                                                      ║
║       Lochy's carefully curated, lovingly maintained,               ║
║       definitely-not-over-engineered dotfiles                       ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝
```

<div align="center">

🏠 **Home is where the dotfiles are** 🏠

[![Made with ❤️](https://img.shields.io/badge/made%20with-%E2%9D%A4%EF%B8%8F-red.svg)](https://github.com/loklaan/dotfiles)
[![Powered by chezmoi](https://img.shields.io/badge/powered%20by-chezmoi-blue)](https://www.chezmoi.io/)
[![mise](https://img.shields.io/badge/dependencies-mise-orange)](https://mise.jdx.dev/)

</div>

---

## 🎯 The Stack

Built on the shoulders of giants (and some really clever CLIs):

- 🚀 **[`chezmoi`](https://www.chezmoi.io/)** - Because manually symlinking dotfiles is so 2015
- 📦 **[`mise`](https://mise.jdx.dev/)** - Dependencies that actually work across machines
- 🔐 **[Bitwarden Secrets Manager](https://bitwarden.com/help/secrets-manager-cli/)** - Secrets that stay secret
- ⚡ **`install.sh`** - One script to rule them all

## 📥 Installation

> **Ready to rice your machine?** Let's go! 🚀

### 🌟 The One-Liner (Full Install)

For a fresh machine (includes chezmoi, bitwarden, mise, and everything else):

```bash
curl -fsSL https://raw.githubusercontent.com/loklaan/dotfiles/main/install.sh | \
  CONFIG_SIGNING_KEY=... \
  CONFIG_BWS_ACCESS_TOKEN=... \
  bash
```

**Pro tip:** You'll need those environment variables ready. See the reference below! 👇

### 📝 Environment Variables Reference

| Variable | Required? | What's it for? |
|----------|-----------|----------------|
| `CONFIG_BWS_ACCESS_TOKEN` | ✅ Yes | Authenticating with Bitwarden Secrets Manager |
| `CONFIG_SIGNING_KEY` | ✅ Yes | Your GPG signing key (find it with `gpg -K`) |
| `CONFIG_GH_USER` | ⭐ Optional | Your GitHub username for dotfiles |
| `CONFIG_EMAIL` | ⭐ Optional | Personal email for Git config |
| `CONFIG_EMAIL_WORK` | ⭐ Optional | Work email for Git config |

### 🔄 Keeping Things Fresh (Update)

Already installed? Stay up to date:

```bash
# The quick way
BWS_ACCESS_TOKEN=... chezmoi update

# Or if you like to live dangerously
chezmoi cd
git pull
BWS_ACCESS_TOKEN=... chezmoi apply
```

### 🧪 Testing Before You Wreck

Want to test the install without touching your pristine system?

```bash
./install.test.sh
```

This spins up a Docker container (Alpine Linux) and runs the full installation with dummy data from `chezmoi.test.toml`. It's like a safety net, but for your dotfiles! 🎪

## ✨ Features (aka The Good Stuff)

This isn't just another dotfiles repo. Here's what makes it special:

### 🎨 Modular Zsh Configuration
Clean, organized shell setup with separate `init/` modules for env, login, options, plugins, and prompt. No more 500-line `.zshrc` nightmares!

### 🛠️ Custom Utilities
Handcrafted tools living in `~/.local/bin/`:
- 📢 `notify` - Desktop notifications that actually work
- 🗑️ `safe-rm` - Because `rm -rf /` shouldn't be that easy
- 🔤 `font-install` - Install fonts without the GUI hassle

### 📦 Pinned Dependencies
Chezmoi externals manage versioned archives for:
- Zsh plugins (because breaking changes are a thing)
- Tmux plugins (tabs within tabs within... you get it)
- Fonts (because Comic Sans is never the answer)

### 🤖 Automation Magic
Post-install scripts in `.chezmoiscripts/` handle the boring stuff automatically. Set it and forget it!

### 🧠 Claude Code Integration
MCP server configs baked right in:
- `effect-docs` for TypeScript wizardry
- `otter` for work-specific goodness

### 🐳 Docker Testing
Full end-to-end testing in Docker means you can break things safely. Living on the edge, responsibly!

## 🗂️ Structure (Where Everything Lives)

Here's how this dotfiles kingdom is organized:

```
🏠 home/
├── 📦 .chezmoiexternals/      # External deps (plugins, fonts) via archives
├── 🤖 .chezmoiscripts/        # Pre & post-install automation scripts
├── 💻 dev/                    # Code projects (work, personal, open source)
├── ⚙️  private_dot_config/
│   ├── 🐚 private_zsh/        # Modular zsh configuration
│   │   ├── init/             # Startup modules (env, login, options, etc.)
│   │   └── lib/              # Utility libraries (ai, ssh, tracing, etc.)
│   └── ...                   # Other tool configs (git, tmux, nvim, etc.)
└── 🛠️  private_dot_local/
    └── bin/                  # Custom utilities (notify, safe-rm, etc.)
```

> **Note:** The `private_` prefix is chezmoi's way of saying "don't show this in the repo as a dot-prefixed file". It gets stripped when applied to your system!

## 💼 Code Projects (Where the Magic Happens)

The `~/dev/` directory keeps things organized by ownership and purpose:

<div align="center">

### 🎨 [`~/dev/canva/`](http://lifeatcanva.com/) - Work Projects
**I work at Canva, building tools that empower creativity!** 🚀
We're hiring amazing engineers who want to make design accessible to everyone.
[**Come build with us!** →](http://lifeatcanva.com/)

</div>

---

- 🙋 **`~/dev/me/`** - Personal projects and experiments
- 🌍 **`~/dev/open/`** - Open source projects (mostly contributions to others' work)

### 📁 The `.me/` Convention

In repos where I'm actively developing, you might find a `.me/` directory. This is my personal scratch space for:
- 🔧 Helper scripts and utilities
- 📊 Temporary data and analysis
- 📓 Jupyter notebooks and experiments
- 🗒️ Personal notes and TODOs

These aren't managed by chezmoi and are gitignored globally. Your own private workspace within the repo!

## 📚 Conventions (The Rules of Engagement)

### 🐚 Shell Stuff

Built with **zsh** in mind (because it's 2026, people). Here are the docs you'll actually need:

- 📖 [**Zsh Options**](https://zsh.sourceforge.io/Doc/Release/Options.html) - All the knobs and switches (use `[[ -o option_name ]]` for runtime checks)
- 🚀 [**Startup Files**](https://zsh.sourceforge.io/Intro/intro_3.html) - Understanding the zsh loading order (yes, it's complicated)

### 🔨 Bash Scripts

The automation scripts in `.chezmoiscripts/` follow battle-tested patterns from [loklaan/knowledge](https://github.com/loklaan/knowledge/blob/master/shell/bash.md). Because bash doesn't have to be chaotic!

---

<div align="center">

### 🎉 That's it! Happy dotfiling!

**Questions? Issues? PRs?**
This is a personal repo, but feel free to open an issue or steal ideas!

Made with ❤️ and way too much time in the terminal

</div>
