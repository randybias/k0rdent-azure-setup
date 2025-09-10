---
id: task-059
title: Fix KOF Istio installation to wait for Sveltos CRDs
status: Done
assignee: []
created_date: '2025-09-10 15:21'
labels: []
dependencies: []
---

## Description

The kof-istio Helm chart requires Sveltos ClusterProfile CRDs to be present before installation. Added retry logic with timeout to wait for CRDs before attempting Istio installation.

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Istio installation waits for Sveltos CRDs,Installation succeeds when CRDs are available,Timeout after 10 minutes if CRDs not available
<!-- AC:END -->

## Implementation Notes

Fixed the install_istio_for_kof function in etc/kof-functions.sh to wait up to 10 minutes for ClusterProfile CRD to be available. Also checks for Sveltos controller readiness before proceeding. Updated KOF version to 1.3.0 in config.
