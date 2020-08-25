#!/bin/sh
if [ -d $HOME/jarvis-nifi ];then
	sudo chown ubuntu:ubuntu $HOME/jarvis-nifi/logs/*
	cp $HOME/jarvis-nifi/logs/nifi-app.log ./
fi

if [ -d $HOME/minifi ];then
	sudo chown ubuntu:ubuntu $HOME/minifi/minifi-0.5.0/logs/*
	cp $HOME/minifi/minifi-0.5.0/logs/minifi-app.log ./
fi

git add .
git commit -m "$1"
git push
