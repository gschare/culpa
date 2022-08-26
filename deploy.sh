#!/bin/bash

SITE_DIR="_site/"
SITE_BRANCH="gh-pages"

stack build.hs

git add -f $SITE_DIR && git commit -m "Build site $(date +'%d %b %Y %T')"
git subtree push --prefix $SITE_DIR origin $SITE_BRANCH
