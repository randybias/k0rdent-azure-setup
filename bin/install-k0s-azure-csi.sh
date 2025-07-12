#!/usr/bin/env bash

# Script: install-k0s-azure-csi.sh
# Purpose: Install Azure Disk CSI Driver on k0s management cluster
# Usage: bash install-k0s-azure-csi.sh [deploy|uninstall|status|help]
# Prerequisites: 
#   - k0s cluster deployed with kubeconfig available
#   - Azure credentials configured (run setup-azure-cluster-deployment.sh first)
#   - Required for KOF deployment when KOF components need persistent storage
# Note: This is ONLY needed as a prerequisite for KOF deployment.
#       Child clusters deployed by k0rdent will have CSI configured automatically.

set -euo pipefail

# Load central configuration and common functions
source ./etc/k0rdent-config.sh
source ./etc/common-functions.sh
source ./etc/state-management.sh

# Output directory and file
K0SCTL_DIR="./k0sctl-config"
KUBECONFIG_FILE="$K0SCTL_DIR/${K0RDENT_PREFIX}-kubeconfig"

# Azure CSI Driver version
AZURE_CSI_VERSION="${AZURE_CSI_VERSION:-v1.30.0}"

# Script-specific functions
show_usage() {
    print_usage "$0" \
        "  deploy     Install Azure Disk CSI Driver on k0s cluster
  uninstall  Remove Azure Disk CSI Driver from cluster
  status     Show CSI driver installation status
  help       Show this help message" \
        "  -y, --yes        Skip confirmation prompts" \
        "  $0 deploy        # Install Azure CSI
  $0 status        # Check installation status
  $0 uninstall     # Remove Azure CSI"
}

check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check for kubeconfig
    if ! check_file_exists "$KUBECONFIG_FILE" "Kubeconfig file"; then
        print_error "Kubeconfig not found. Run: ./bin/install-k0s.sh deploy"
        return 1
    fi
    
    export KUBECONFIG="$KUBECONFIG_FILE"
    
    # Test kubectl connectivity
    if ! kubectl get nodes &>/dev/null; then
        print_error "Cannot connect to Kubernetes cluster. Ensure VPN is connected."
        return 1
    fi
    
    # Check if Azure credentials exist
    if [[ ! -f "config/azure-credentials.yaml" ]]; then
        print_error "Azure credentials not found. Run: ./bin/setup-azure-cluster-deployment.sh setup"
        return 1
    fi
    
    print_success "Prerequisites satisfied"
    return 0
}

create_azure_cloud_provider_config() {
    print_info "Creating Azure cloud provider configuration..."
    
    # Load Azure credentials
    local subscription_id=$(yq eval '.azure.subscription_id' config/azure-credentials.yaml)
    local tenant_id=$(yq eval '.azure.tenant_id' config/azure-credentials.yaml)
    local client_id=$(yq eval '.azure.client_id' config/azure-credentials.yaml)
    local client_secret=$(yq eval '.azure.client_secret' config/azure-credentials.yaml)
    
    # Get resource group from config
    local resource_group="${RG}"
    local location="${AZURE_LOCATION}"
    local vnet_name="${VNET_PREFIX}"
    local subnet_name="${SUBNET_PREFIX}"
    
    # Create cloud config
    cat <<EOF > /tmp/azure-cloud-config.json
{
    "cloud": "AzurePublicCloud",
    "tenantId": "$tenant_id",
    "subscriptionId": "$subscription_id",
    "aadClientId": "$client_id",
    "aadClientSecret": "$client_secret",
    "resourceGroup": "$resource_group",
    "location": "$location",
    "vnetName": "$vnet_name",
    "subnetName": "$subnet_name",
    "securityGroupName": "${K0RDENT_PREFIX}-nsg",
    "vnetResourceGroup": "$resource_group",
    "useManagedIdentityExtension": false,
    "useInstanceMetadata": true,
    "vmType": "standard"
}
EOF
    
    # Create Kubernetes secret
    kubectl create secret generic azure-cloud-provider \
        --from-file=cloud-config=/tmp/azure-cloud-config.json \
        -n kube-system \
        --dry-run=client -o yaml | kubectl apply -f -
    
    rm -f /tmp/azure-cloud-config.json
    print_success "Azure cloud provider config created"
}

create_csi_driver_yaml() {
    # Create CSI Driver object
    cat <<EOF | kubectl apply -f -
---
apiVersion: storage.k8s.io/v1
kind: CSIDriver
metadata:
  name: disk.csi.azure.com
spec:
  attachRequired: true
  podInfoOnMount: false
  fsGroupPolicy: File
EOF
}

create_csi_controller_yaml() {
    # Create CSI Controller deployment
    cat <<EOF | kubectl apply -f -
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: csi-azuredisk-controller
  namespace: kube-system
spec:
  replicas: 2
  selector:
    matchLabels:
      app: csi-azuredisk-controller
  template:
    metadata:
      labels:
        app: csi-azuredisk-controller
    spec:
      hostNetwork: true
      serviceAccountName: csi-azuredisk-controller-sa
      nodeSelector:
        kubernetes.io/os: linux
      priorityClassName: system-cluster-critical
      securityContext:
        seccompProfile:
          type: RuntimeDefault
      tolerations:
        - key: "node-role.kubernetes.io/master"
          operator: "Exists"
          effect: "NoSchedule"
        - key: "node-role.kubernetes.io/controlplane"
          operator: "Exists"
          effect: "NoSchedule"
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
      containers:
        - name: csi-provisioner
          image: registry.k8s.io/sig-storage/csi-provisioner:v4.0.0
          args:
            - "--feature-gates=Topology=true,HonorPVReclaimPolicy=true"
            - "--csi-address=\$(ADDRESS)"
            - "--v=2"
            - "--timeout=30s"
            - "--leader-election"
            - "--leader-election-namespace=kube-system"
            - "--worker-threads=100"
            - "--extra-create-metadata=true"
            - "--strict-topology=true"
            - "--kube-api-qps=50"
            - "--kube-api-burst=100"
          env:
            - name: ADDRESS
              value: /csi/csi.sock
          volumeMounts:
            - mountPath: /csi
              name: socket-dir
          resources:
            limits:
              memory: 500Mi
            requests:
              cpu: 10m
              memory: 20Mi
        - name: csi-attacher
          image: registry.k8s.io/sig-storage/csi-attacher:v4.5.0
          args:
            - "-v=2"
            - "-csi-address=\$(ADDRESS)"
            - "-timeout=1200s"
            - "-leader-election"
            - "-leader-election-namespace=kube-system"
            - "-worker-threads=1000"
            - "-kube-api-qps=200"
            - "-kube-api-burst=400"
          env:
            - name: ADDRESS
              value: /csi/csi.sock
          volumeMounts:
            - mountPath: /csi
              name: socket-dir
          resources:
            limits:
              memory: 500Mi
            requests:
              cpu: 10m
              memory: 20Mi
        - name: csi-snapshotter
          image: registry.k8s.io/sig-storage/csi-snapshotter:v6.3.3
          args:
            - "-csi-address=\$(ADDRESS)"
            - "-leader-election"
            - "--leader-election-namespace=kube-system"
            - "-v=2"
          env:
            - name: ADDRESS
              value: /csi/csi.sock
          volumeMounts:
            - mountPath: /csi
              name: socket-dir
          resources:
            limits:
              memory: 200Mi
            requests:
              cpu: 10m
              memory: 20Mi
        - name: csi-resizer
          image: registry.k8s.io/sig-storage/csi-resizer:v1.9.3
          args:
            - "-csi-address=\$(ADDRESS)"
            - "-v=2"
            - "-leader-election"
            - "--leader-election-namespace=kube-system"
            - '-handle-volume-inuse-error=false'
            - '-feature-gates=RecoverVolumeExpansionFailure=true'
            - "-timeout=240s"
          env:
            - name: ADDRESS
              value: /csi/csi.sock
          volumeMounts:
            - mountPath: /csi
              name: socket-dir
          resources:
            limits:
              memory: 500Mi
            requests:
              cpu: 10m
              memory: 20Mi
        - name: liveness-probe
          image: registry.k8s.io/sig-storage/livenessprobe:v2.12.0
          args:
            - --csi-address=/csi/csi.sock
            - --probe-timeout=3s
            - --health-port=29602
            - --v=2
          volumeMounts:
            - name: socket-dir
              mountPath: /csi
          resources:
            limits:
              memory: 100Mi
            requests:
              cpu: 10m
              memory: 20Mi
        - name: azuredisk
          image: registry.k8s.io/k8s-staging-cloud-provider-azure/azure-csi-driver:v1.30.0
          args:
            - "--v=5"
            - "--endpoint=\$(CSI_ENDPOINT)"
            - "--metrics-address=0.0.0.0:29604"
            - "--user-agent-suffix=OSS-kubectl"
            - "--disable-avset-nodes=false"
            - "--allow-empty-cloud-config=false"
          ports:
            - containerPort: 29602
              name: healthz
              protocol: TCP
            - containerPort: 29604
              name: metrics
              protocol: TCP
          livenessProbe:
            failureThreshold: 5
            httpGet:
              path: /healthz
              port: healthz
            initialDelaySeconds: 30
            timeoutSeconds: 10
            periodSeconds: 30
          env:
            - name: CSI_ENDPOINT
              value: unix:///csi/csi.sock
            - name: AZURE_CREDENTIAL_FILE
              valueFrom:
                configMapKeyRef:
                  name: azure-cred-file
                  key: path
                  optional: true
            - name: AZURE_CLOUD_CONFIG_FILE
              value: /etc/kubernetes/azure.json
          imagePullPolicy: IfNotPresent
          volumeMounts:
            - mountPath: /csi
              name: socket-dir
            - mountPath: /etc/kubernetes/
              name: azure-cred
          resources:
            limits:
              memory: 500Mi
            requests:
              cpu: 10m
              memory: 20Mi
      volumes:
        - name: socket-dir
          emptyDir: {}
        - name: azure-cred
          secret:
            secretName: azure-cloud-provider
EOF
}

create_csi_node_yaml() {
    # Create CSI Node DaemonSet
    cat <<EOF | kubectl apply -f -
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: csi-azuredisk-node
  namespace: kube-system
spec:
  updateStrategy:
    rollingUpdate:
      maxUnavailable: 1
    type: RollingUpdate
  selector:
    matchLabels:
      app: csi-azuredisk-node
  template:
    metadata:
      labels:
        app: csi-azuredisk-node
    spec:
      hostNetwork: true
      dnsPolicy: Default
      serviceAccountName: csi-azuredisk-node-sa
      nodeSelector:
        kubernetes.io/os: linux
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: type
                    operator: NotIn
                    values:
                      - virtual-kubelet
      priorityClassName: system-node-critical
      securityContext:
        seccompProfile:
          type: RuntimeDefault
      tolerations:
        - operator: "Exists"
      containers:
        - name: liveness-probe
          volumeMounts:
            - mountPath: /csi
              name: socket-dir
          image: registry.k8s.io/sig-storage/livenessprobe:v2.12.0
          args:
            - --csi-address=/csi/csi.sock
            - --probe-timeout=3s
            - --health-port=29603
          resources:
            limits:
              memory: 100Mi
            requests:
              cpu: 10m
              memory: 20Mi
        - name: node-driver-registrar
          image: registry.k8s.io/sig-storage/csi-node-driver-registrar:v2.10.0
          args:
            - --csi-address=\$(ADDRESS)
            - --kubelet-registration-path=\$(DRIVER_REG_SOCK_PATH)
            - --v=2
          livenessProbe:
            exec:
              command:
                - /csi-node-driver-registrar
                - --kubelet-registration-path=\$(DRIVER_REG_SOCK_PATH)
                - --mode=kubelet-registration-probe
            initialDelaySeconds: 30
            timeoutSeconds: 15
          env:
            - name: ADDRESS
              value: /csi/csi.sock
            - name: DRIVER_REG_SOCK_PATH
              value: /var/lib/k0s/kubelet/plugins/disk.csi.azure.com/csi.sock
          volumeMounts:
            - name: socket-dir
              mountPath: /csi
            - name: registration-dir
              mountPath: /registration
          resources:
            limits:
              memory: 100Mi
            requests:
              cpu: 10m
              memory: 20Mi
        - name: azuredisk
          image: registry.k8s.io/k8s-staging-cloud-provider-azure/azure-csi-driver:v1.30.0
          args:
            - "--v=5"
            - "--endpoint=\$(CSI_ENDPOINT)"
            - "--nodeid=\$(KUBE_NODE_NAME)"
            - "--enable-perf-optimization=true"
          ports:
            - containerPort: 29603
              name: healthz
              protocol: TCP
          livenessProbe:
            failureThreshold: 5
            httpGet:
              path: /healthz
              port: healthz
            initialDelaySeconds: 30
            timeoutSeconds: 10
            periodSeconds: 30
          env:
            - name: CSI_ENDPOINT
              value: unix:///csi/csi.sock
            - name: KUBE_NODE_NAME
              valueFrom:
                fieldRef:
                  apiVersion: v1
                  fieldPath: spec.nodeName
          securityContext:
            privileged: true
          volumeMounts:
            - mountPath: /csi
              name: socket-dir
            - mountPath: /var/lib/k0s/kubelet/
              mountPropagation: Bidirectional
              name: mountpoint-dir
            - mountPath: /etc/kubernetes/
              name: azure-cred
            - mountPath: /dev
              name: device-dir
            - mountPath: /sys/bus/scsi/devices
              name: sys-devices-dir
            - mountPath: /sys/class/
              name: sys-class
          resources:
            limits:
              memory: 200Mi
            requests:
              cpu: 10m
              memory: 20Mi
      volumes:
        - hostPath:
            path: /var/lib/k0s/kubelet/plugins/disk.csi.azure.com
            type: DirectoryOrCreate
          name: socket-dir
        - hostPath:
            path: /var/lib/k0s/kubelet/
            type: DirectoryOrCreate
          name: mountpoint-dir
        - hostPath:
            path: /var/lib/k0s/kubelet/plugins_registry/
            type: DirectoryOrCreate
          name: registration-dir
        - name: azure-cred
          secret:
            secretName: azure-cloud-provider
        - hostPath:
            path: /dev
            type: Directory
          name: device-dir
        - hostPath:
            path: /sys/bus/scsi/devices
            type: Directory
          name: sys-devices-dir
        - hostPath:
            path: /sys/class/
            type: Directory
          name: sys-class
EOF
}

create_csi_rbac() {
    # Create RBAC resources for CSI driver
    cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: csi-azuredisk-controller-sa
  namespace: kube-system
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: csi-azuredisk-node-sa
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: azuredisk-external-provisioner-role
rules:
  - apiGroups: [""]
    resources: ["persistentvolumes"]
    verbs: ["get", "list", "watch", "create", "delete"]
  - apiGroups: [""]
    resources: ["persistentvolumeclaims"]
    verbs: ["get", "list", "watch", "update"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["csinodes"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["coordination.k8s.io"]
    resources: ["leases"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["snapshot.storage.k8s.io"]
    resources: ["volumesnapshots"]
    verbs: ["get", "list"]
  - apiGroups: ["snapshot.storage.k8s.io"]
    resources: ["volumesnapshotcontents"]
    verbs: ["get", "list"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["volumeattachments"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: azuredisk-csi-provisioner-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: azuredisk-external-provisioner-role
subjects:
  - kind: ServiceAccount
    name: csi-azuredisk-controller-sa
    namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: azuredisk-external-attacher-role
rules:
  - apiGroups: [""]
    resources: ["persistentvolumes"]
    verbs: ["get", "list", "watch", "update", "patch"]
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["csinodes"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["volumeattachments"]
    verbs: ["get", "list", "watch", "update", "patch"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["volumeattachments/status"]
    verbs: ["patch"]
  - apiGroups: ["coordination.k8s.io"]
    resources: ["leases"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: azuredisk-csi-attacher-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: azuredisk-external-attacher-role
subjects:
  - kind: ServiceAccount
    name: csi-azuredisk-controller-sa
    namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: azuredisk-external-snapshotter-role
rules:
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["list", "watch", "create", "update", "patch"]
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get"]
  - apiGroups: ["snapshot.storage.k8s.io"]
    resources: ["volumesnapshotclasses"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["snapshot.storage.k8s.io"]
    resources: ["volumesnapshotcontents"]
    verbs: ["create", "get", "list", "watch", "update", "delete", "patch"]
  - apiGroups: ["snapshot.storage.k8s.io"]
    resources: ["volumesnapshotcontents/status"]
    verbs: ["update", "patch"]
  - apiGroups: ["coordination.k8s.io"]
    resources: ["leases"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: azuredisk-csi-snapshotter-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: azuredisk-external-snapshotter-role
subjects:
  - kind: ServiceAccount
    name: csi-azuredisk-controller-sa
    namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: azuredisk-external-resizer-role
rules:
  - apiGroups: [""]
    resources: ["persistentvolumes"]
    verbs: ["get", "list", "watch", "update", "patch"]
  - apiGroups: [""]
    resources: ["persistentvolumeclaims"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["persistentvolumeclaims/status"]
    verbs: ["update", "patch"]
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["list", "watch", "create", "update", "patch"]
  - apiGroups: ["coordination.k8s.io"]
    resources: ["leases"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: azuredisk-csi-resizer-role
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: azuredisk-external-resizer-role
subjects:
  - kind: ServiceAccount
    name: csi-azuredisk-controller-sa
    namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: csi-azuredisk-controller-secret-role
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: csi-azuredisk-controller-secret-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: csi-azuredisk-controller-secret-role
subjects:
  - kind: ServiceAccount
    name: csi-azuredisk-controller-sa
    namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: csi-azuredisk-node-role
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get"]
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: csi-azuredisk-node-secret-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: csi-azuredisk-node-role
subjects:
  - kind: ServiceAccount
    name: csi-azuredisk-node-sa
    namespace: kube-system
EOF
}

deploy_azure_csi() {
    print_header "Installing Azure Disk CSI Driver"
    
    # Check prerequisites
    if ! check_prerequisites; then
        return 1
    fi
    
    # Create cloud provider config
    create_azure_cloud_provider_config
    
    print_info "Deploying Azure Disk CSI Driver v${AZURE_CSI_VERSION}..."
    
    # Create RBAC resources
    print_info "Creating RBAC resources..."
    create_csi_rbac
    
    # Create CSI Driver
    print_info "Creating CSI Driver..."
    create_csi_driver_yaml
    
    # Create Controller deployment
    print_info "Creating CSI Controller deployment..."
    create_csi_controller_yaml
    
    # Create Node DaemonSet
    print_info "Creating CSI Node DaemonSet..."
    create_csi_node_yaml
    
    print_info "Waiting for CSI driver pods to be ready..."
    kubectl wait --for=condition=ready pod -l app=csi-azuredisk-controller -n kube-system --timeout=300s || true
    kubectl wait --for=condition=ready pod -l app=csi-azuredisk-node -n kube-system --timeout=300s || true
    
    # Create managed-csi StorageClass with ZRS support
    print_info "Creating managed-csi StorageClass with ZRS support..."
    cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: managed-csi
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: disk.csi.azure.com
parameters:
  skuName: StandardSSD_ZRS  # Zone-redundant storage
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOF
    
    # Update state
    update_state "azure_csi_installed" "true"
    add_event "azure_csi_installed" "Azure Disk CSI Driver installed successfully"
    
    print_success "Azure Disk CSI Driver installation completed!"
    
    # Show status
    show_status
}

uninstall_azure_csi() {
    print_header "Uninstalling Azure Disk CSI Driver"
    
    if ! check_prerequisites; then
        return 1
    fi
    
    print_info "Removing Azure Disk CSI Driver..."
    
    # Delete StorageClass
    kubectl delete storageclass managed-csi --ignore-not-found
    
    # Delete CSI driver components
    kubectl delete deployment csi-azuredisk-controller -n kube-system --ignore-not-found
    kubectl delete daemonset csi-azuredisk-node -n kube-system --ignore-not-found
    kubectl delete csidriver disk.csi.azure.com --ignore-not-found
    
    # Delete RBAC resources
    kubectl delete clusterrolebinding azuredisk-csi-provisioner-binding --ignore-not-found
    kubectl delete clusterrole azuredisk-external-provisioner-role --ignore-not-found
    kubectl delete clusterrolebinding azuredisk-csi-attacher-binding --ignore-not-found
    kubectl delete clusterrole azuredisk-external-attacher-role --ignore-not-found
    kubectl delete clusterrolebinding azuredisk-csi-snapshotter-binding --ignore-not-found
    kubectl delete clusterrole azuredisk-external-snapshotter-role --ignore-not-found
    kubectl delete clusterrolebinding azuredisk-csi-resizer-role --ignore-not-found
    kubectl delete clusterrole azuredisk-external-resizer-role --ignore-not-found
    kubectl delete clusterrolebinding csi-azuredisk-controller-secret-binding --ignore-not-found
    kubectl delete clusterrole csi-azuredisk-controller-secret-role --ignore-not-found
    kubectl delete clusterrolebinding csi-azuredisk-node-secret-binding --ignore-not-found
    kubectl delete clusterrole csi-azuredisk-node-role --ignore-not-found
    kubectl delete serviceaccount csi-azuredisk-controller-sa -n kube-system --ignore-not-found
    kubectl delete serviceaccount csi-azuredisk-node-sa -n kube-system --ignore-not-found
    
    # Delete cloud provider secret
    kubectl delete secret azure-cloud-provider -n kube-system --ignore-not-found
    
    # Update state
    update_state "azure_csi_installed" "false"
    add_event "azure_csi_uninstalled" "Azure Disk CSI Driver uninstalled"
    
    print_success "Azure Disk CSI Driver uninstalled successfully"
}

show_status() {
    print_header "Azure Disk CSI Driver Status"
    
    if ! check_prerequisites; then
        return 1
    fi
    
    print_info "CSI Driver Pods:"
    kubectl get pods -n kube-system -l 'app in (csi-azuredisk-controller,csi-azuredisk-node)' 2>/dev/null || print_info "No CSI driver pods found"
    
    echo
    print_info "CSI Drivers:"
    kubectl get csidrivers 2>/dev/null | grep -E "(NAME|disk.csi.azure.com)" || print_info "No CSI drivers found"
    
    echo
    print_info "CSI Nodes:"
    kubectl get csinodes 2>/dev/null || print_info "No CSI nodes found"
    
    echo
    print_info "Storage Classes:"
    kubectl get storageclass 2>/dev/null | grep -E "(NAME|managed-csi)" || print_info "No storage classes found"
    
    echo
    print_info "Persistent Volume Claims:"
    kubectl get pvc -A 2>/dev/null | grep -E "(NAME|managed-csi)" || print_info "No PVCs using managed-csi found"
}

# Store original arguments for handle_standard_commands
ORIGINAL_ARGS=("$@")

# Parse standard arguments to get COMMAND
PARSED_ARGS=$(parse_standard_args "$@")
eval "$PARSED_ARGS"

# Get the command from positional arguments
COMMAND="${POSITIONAL_ARGS[0]:-}"

# Use consolidated command handling
handle_standard_commands "$0" "deploy uninstall status help" \
    "deploy" "deploy_azure_csi" \
    "uninstall" "uninstall_azure_csi" \
    "status" "show_status" \
    "usage" "show_usage"