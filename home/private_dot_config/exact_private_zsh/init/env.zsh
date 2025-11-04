# Locale
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8

# User
export DEFAULT_USER=loch
export EDITOR='idea --wait'

# Pathing
export PATH="$HOME/.local/bin:{{ .brewprefix }}/sbin:{{ .brewprefix }}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# XDG
export XDG_CACHE_HOME="$HOME/Library/Caches"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"

# Filesystem inodes
ulimit -n 10240 # Raises the limit for open files, which is important for large git repos
bgnotify_threshold=8
