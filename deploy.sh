#!/bin/bash
set -x

echo -e "\033[0;32mDeploying updates to GitHub...\033[0m"

# Clean up public
rm -rf public/

# Add master into public as git submodule
git submodule add --force -b master git@github.com:networkop/networkop.github.io.git public

# Build the project.
hugo-0.52-extended -t academic # if using a theme, replace with `hugo -t <YOURTHEME>`

# Go To Public folder
cd public

# Add changes to git.
git add -A .

# Commit changes.
msg="rebuilding site `date`"
if [ $# -eq 1 ]
  then msg="$1"
fi
git commit -m "$msg"

# Push source and build repos.
git push origin master

# Come Back up to the Project Root
cd ..
