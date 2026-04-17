if [[ -n "$TMUX_PANE" ]]; then
    _resume_file="${TMPDIR:-/tmp}/tmux-resume-${TMUX_PANE#%}.zsh"
    if [[ -r "$_resume_file" ]]; then
        _resume_src="$_resume_file"
        rm -f "$_resume_file"
        source "$_resume_src"
    fi
    unset _resume_file _resume_src
fi
