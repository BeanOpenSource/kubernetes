#!/bin/bash

set -euo pipefail

# Internal constants
_KUBELET_CONFIG="/var/lib/kubelet/config.yaml"
_KUBECONFIG="/etc/kubernetes/kubeconfig"
_CONTAINERD_SOCKET="/run/containerd/containerd.sock"
_POD_MANIFEST_PATH="/etc/kubernetes/manifests"
_POD_YAML_FILE="${_POD_MANIFEST_PATH}/test-pod.yaml"
_CNI_CONF_DIR="/etc/cni/net.d"
_CNI_CONF_FILE="${_CNI_CONF_DIR}/10-bridge.conf"

# Log functions
log_info() {
    echo -e "[INFO] $1"
}

log_error() {
    echo -e "[ERROR] $1" >&2
    exit 1
}

# Helper functions
_validate_kubelet_binary() {
    if [ -z "$_KUBELET_BINARY" ]; then
        log_error "Kubelet binary path not provided! Please pass it as an argument, e.g., ./script.sh /path/to/kubelet"
    fi

    if [ ! -x "$_KUBELET_BINARY" ]; then
        log_error "Kubelet binary at $_KUBELET_BINARY is not executable or does not exist!"
    fi

    log_info "Using kubelet binary: $_KUBELET_BINARY"
}

_install_containerd() {
    log_info "Installing containerd..."
    sudo apt update
    sudo apt install -y containerd.io
    sudo mkdir -p /etc/containerd
    containerd config default | sudo tee /etc/containerd/config.toml
    sudo systemctl restart containerd
    log_info "Containerd installed and configured successfully."
}

_install_cni_plugins() {
    log_info "Installing CNI plugins..."
    sudo mkdir -p /opt/cni/bin
    curl -L https://github.com/containernetworking/plugins/releases/download/v1.2.0/cni-plugins-linux-amd64-v1.2.0.tgz | sudo tar -C /opt/cni/bin -xz
    log_info "CNI plugins installed successfully."
}

_sample_configure_cni() {
    log_info "Configuring CNI network..."
    sudo mkdir -p "$_CNI_CONF_DIR"
    cat <<EOF | sudo tee "$_CNI_CONF_FILE"
{
  "cniVersion": "0.4.0",
  "name": "bridge",
  "type": "bridge",
  "bridge": "cni0",
  "isGateway": true,
  "ipMasq": true,
  "ipam": {
    "type": "host-local",
    "ranges": [
      [
        {
          "subnet": "10.244.0.0/16"
        }
      ]
    ],
    "routes": [
      { "dst": "0.0.0.0/0" }
    ]
  }
}
EOF
    log_info "CNI network configuration created at $_CNI_CONF_FILE."
}

_create_kubelet_config() {
    log_info "Creating Kubelet configuration file at $_KUBELET_CONFIG..."
    sudo mkdir -p "$(dirname "$_KUBELET_CONFIG")"
    sudo tee "$_KUBELET_CONFIG" > /dev/null <<EOF
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
address: 0.0.0.0
authentication:
  anonymous:
    enabled: true
  webhook:
    enabled: false
authorization:
  mode: AlwaysAllow
failSwapOn: false
containerRuntimeEndpoint: unix:///run/containerd/containerd.sock
staticPodPath: /etc/kubernetes/manifests
cgroupDriver: systemd
clusterDomain: cluster.local
clusterDNS:
  - 10.96.0.10
EOF
    log_info "Kubelet configuration file created successfully."
}

_check_and_create_kubelet_config() {
    log_info "Checking for Kubelet configuration file..."
    if [ ! -f "$_KUBELET_CONFIG" ]; then
        _create_kubelet_config
    else
        log_info "Kubelet configuration file already exists at $_KUBELET_CONFIG."
    fi
}

_check_and_install_containerd() {
    log_info "Checking containerd..."
    if ! command -v containerd &> /dev/null; then
        _install_containerd
    else
        log_info "Containerd is already installed."
    fi

    if ! systemctl is-active --quiet containerd; then
        log_info "Starting containerd service..."
        sudo systemctl restart containerd
    fi

    if [ ! -S "$_CONTAINERD_SOCKET" ]; then
        log_error "Containerd socket not found at $_CONTAINERD_SOCKET!"
    fi
}

_check_and_install_cni_plugins() {
    log_info "Checking CNI plugins..."
    if [ ! -d "/opt/cni/bin" ] || [ -z "$(ls -A /opt/cni/bin)" ]; then
        _install_cni_plugins
    else
        log_info "CNI plugins are already installed."
    fi

    log_info "Checking CNI configuration..."
    if [ ! -f "$_CNI_CONF_FILE" ]; then
        _sample_configure_cni
    else
        log_info "CNI configuration already exists at $_CNI_CONF_FILE."
    fi
    sudo systemctl restart containerd
}

_check_kubelet_process() {
    log_info "Checking if kubelet process is running..."
    if pgrep -f "kubelet" &> /dev/null; then
        log_info "Kubelet process is running."
    else
        log_error "Kubelet process is not running! Continuing with setup..."
    fi
}

_generate_pod_manifest() {
    log_info "Generating Pod YAML manifest..."
    sudo mkdir -p "$_POD_MANIFEST_PATH"
    cat <<EOF | sudo tee "$_POD_YAML_FILE"
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
  namespace: default
spec:
  containers:
  - name: nginx
    image: nginx:latest
    ports:
    - containerPort: 80
EOF
    log_info "Pod YAML manifest generated at $_POD_YAML_FILE."
}

_start_kubelet() {
    log_info "Starting kubelet with --pod-manifest-path..."
    sudo "$_KUBELET_BINARY" \
      --config=$_KUBELET_CONFIG \
      --container-runtime-endpoint=$_CONTAINERD_SOCKET \
      --pod-manifest-path=$_POD_MANIFEST_PATH \
      --fail-swap-on=false \
      --v=2 &

    sleep 5  

    if ! pgrep -f "kubelet" &> /dev/null; then
        log_error "Kubelet failed to start! Check the configuration and logs for details."
    fi
    log_info "Kubelet started successfully with --pod-manifest-path=$_POD_MANIFEST_PATH."
}

_check_kubelet_status() {
    log_info "Checking if kubelet is running..."
    if ! pgrep -f "kubelet" &> /dev/null; then
        log_error "Kubelet is not running!"
    fi
    log_info "Kubelet is running."
}

_main() {
    log_info "Starting Kubelet setup and Pod creation in standalone mode..."

    _validate_kubelet_binary
    _check_and_install_containerd
    _check_and_install_cni_plugins
    _check_kubelet_process
    _generate_pod_manifest
    _check_and_create_kubelet_config
    _start_kubelet
    _check_kubelet_status

    log_info "Kubelet setup completed, and Pod YAML has been loaded successfully."
}

# Parse arguments
if [ $# -ne 1 ]; then
    log_error "Usage: $0 /path/to/kubelet"
fi
_KUBELET_BINARY="$1"

# Execute main function
_main
