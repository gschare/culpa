#!/bin/bash

SITE_DIR="_site/"
SITE_BRANCH="gh-pages"

stack build.hs

git add -f $SITE_DIR && git commit -m "Build site $(date +'%d %b %Y %T')"
git push -d origin $SITE_BRANCH     # delete branch
git subtree push --prefix $SITE_DIR origin $SITE_BRANCH
#git reset HEAD~1                    # reset the commit only in the current branch
