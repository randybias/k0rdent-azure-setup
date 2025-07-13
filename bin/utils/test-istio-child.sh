#!/usr/bin/env bash
#
bin/create-child.sh --cluster-name child-with-istio --cloud azure --location southeastasia --cp-instance-size Standard_A4_v2 --worker-instance-size Standard_A4_v2 --root-volume-size 64 --namespace kcm-system --template azure-standalone-cp-1-0-8 --credential azure-cluster-credential --cp-number 1 --worker-number 1 --cluster-identity-name azure-cluster-identity --cluster-identity-namespace kcm-system --cluster-labels k0rdent.mirantis.com/kof-storage-secrets=true,k0rdent.mirantis.com/kof-cluster-role=child
