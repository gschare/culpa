#!/bin/bash

SITE_DIR="_site/"
SITE_BRANCH="gh-pages"

stack build.hs

git add $SITE_DIR
git commit -m "Build site $(date)"
git push -d origin $SITE_BRANCH
git subtree push --prefix $SITE_DIR origin $SITE_BRANCH
git reset HEAD~1
