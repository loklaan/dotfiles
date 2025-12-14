#!/bin/bash

# Loop over nested directories
for dir in $(find ${ZPLUG_REPOS:?"Looks like zplug is not installed in the shell. Exiting."} -type d -name ".git")
do
  # Enter directory
  pushd ${dir%/*} > /dev/null

  # Get repo name
  repo=$(basename `git rev-parse --show-toplevel`)

  # Get remote URL
  url=$(git config --get remote.origin.url)

  # Get latest commit hash
  commit=$(git rev-parse --short HEAD)

  # Construct tarball URL
  tarball="${url%.*}/archive/${commit}.tar.gz"

  # Output TOML
  echo "[\".config/zsh/plugins/${repo}\"]"
  echo "    type = \"archive\""
  echo "    url = \"${tarball}\""
  echo "    exact = true"
  echo "    stripComponents = 1"
  echo "    refreshPeriod = \"168h\""

  # Exit directory
  popd > /dev/null
done
