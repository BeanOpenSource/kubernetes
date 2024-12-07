# Kubelet Setup and Testing Scripts

## Features

- **Containerd Installation**: Automatically installs and configures the containerd container runtime.
- **CNI Plugin Installation**: Installs the necessary CNI plugins for pod networking.
- **Kubelet Setup**: Starts the kubelet with the specified configuration, running in standalone mode.
- **Pod Manifest Creation**: Automatically generates a simple pod manifest (`nginx` container) and loads it via the kubelet.
- **Error Handling**: Ensures that all required dependencies are checked and installed before running kubelet.

## Prerequisites

- Ubuntu or a similar Linux distribution.
- Access to `sudo` privileges.
- Kubelet binary (either precompiled or built from source).
- Containerd must be installed and running.

## Installation


### Step 1: Run the Script

Run the `bash_scripts.sh` script to set up the kubelet, containerd, and CNI plugins:

```bash
sudo ./bash_scripts.sh the/path/to/kubelet/binary
```

The script will:
1. Check for the required dependencies (containerd, CNI plugins, kubelet).
2. Install any missing components.
3. Generate a pod manifest for testing.
4. Start the kubelet in standalone mode with the generated manifest.

then check the pod using the command 

```bash
sudo crictl ps
```

### Step 2: Remove Old Pods

If you need to remove an old pod, you can:

clean up containerd-managed pods using `crictl`:

```bash
sudo crictl pods      # List all pods
sudo crictl stopp <pod-id>   # Stop a pod
sudo crictl rm <container-id>     # Remove a pod
``