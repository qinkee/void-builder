# Void Desktop Docker Test Environment

This Docker environment provides Ubuntu 22.04 desktop with VNC access for testing the Void editor.

## Features

- Ubuntu 22.04 with XFCE desktop environment
- VNC server for remote desktop access
- noVNC for web-based access (no VNC client needed)
- Pre-installed Void editor
- Chinese font support
- Workspace volume mount for file persistence

## Prerequisites

- Docker and Docker Compose installed
- Port 5901 and 6080 available

## Quick Start

### 1. Build and Start

```bash
# Build and start the container
./run.sh build
./run.sh up
```

Or manually:

```bash
# Build the image
docker-compose build

# Start the container
docker-compose up -d
```

### 2. Access the Desktop

You have two options to access the desktop:

#### Option A: Web Browser (Recommended)
- Open: http://localhost:6080/vnc.html
- Password: `void`

#### Option B: VNC Client
- Server: `localhost:5901`
- Password: `void`

### 3. Launch Void Editor

Once connected to the desktop:
1. Click on the Void icon on the desktop
2. Or open Terminal and run: `/usr/share/void/void --no-sandbox`

## Usage

### Basic Commands

```bash
# Start container
./run.sh start

# Stop container
./run.sh stop

# Restart container
./run.sh restart

# View logs
./run.sh logs

# Enter container shell
./run.sh shell

# Remove container
./run.sh down
```

### Update Void Version

```bash
# Update to a specific version
./run.sh update 1.99.30045
```

### File Persistence

Files saved in `/home/void/workspace` inside the container will be available in `./workspace` on your host.

## Troubleshooting

### Container Won't Start

```bash
# Check logs
./run.sh logs

# Clean up and rebuild
./run.sh clean
./run.sh build
./run.sh up
```

### VNC Connection Issues

1. Ensure ports 5901 and 6080 are not in use:
```bash
lsof -i :5901
lsof -i :6080
```

2. Check container status:
```bash
./run.sh status
```

3. Restart VNC server inside container:
```bash
./run.sh shell
# Inside container:
vncserver -kill :1
vncserver :1 -geometry 1920x1080 -depth 24
```

### Void Editor Issues

If Void doesn't start, try running with debug flags:
```bash
./run.sh shell
# Inside container:
/usr/share/void/void --no-sandbox --verbose
```

### Check Roo-Code Extension

To verify if Roo-Code extension is installed:
```bash
./run.sh shell
# Inside container:
ls -la /usr/share/void/resources/app/extensions/ | grep -i roo
```

## Configuration

### Change Resolution

Edit `docker-compose.yml`:
```yaml
environment:
  - VNC_RESOLUTION=1920x1080  # Change this
```

### Change VNC Password

Edit the Dockerfile and rebuild:
```dockerfile
RUN echo "your_password" | vncpasswd -f > /home/void/.vnc/passwd
```

## Security Note

This setup is for testing purposes only. The VNC server is configured without encryption. For production use, consider:
- Using SSH tunneling for VNC
- Implementing SSL/TLS for noVNC
- Using stronger passwords
- Restricting network access

## System Requirements

- Minimum 2GB RAM
- 10GB free disk space
- Docker with compose support

## Known Issues

1. Hardware acceleration is limited in Docker
2. Audio may not work properly
3. Some GPU-accelerated features might be disabled

## Support

For issues related to:
- Docker setup: Check this README
- Void editor: https://github.com/TIMtechnology/void-builder
- VNC issues: Check container logs with `./run.sh logs`