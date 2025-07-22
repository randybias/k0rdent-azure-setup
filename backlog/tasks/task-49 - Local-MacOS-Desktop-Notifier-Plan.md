---
id: task-49
title: Local MacOS Desktop Notifier Plan
status: To Do
assignee: []
created_date: '2025-07-22'
labels: []
dependencies: []
priority: low
---

## Description

Create a plan to create an asynchronous script that runs during deployments, monitors deployment events and sends a desktop notification for new events.  It should start at the beginning of deployments after the events file is created.  It should require a new command line argument: --with-desktop-notifications.

Two different options to send notifications include:

- hammerspoon
- osascript

But other options should be investigated.
