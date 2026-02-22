# Alpine Base Image

A minimal Alpine Linux base image with supervisor, dumb-init, and user support for running containers as non-root users.

## Important: Root Not Supported

**This container MUST run as a non-root user.** The container will refuse to start if running as UID 0 (root). Use the `user:` directive in docker-compose to specify a non-root user.

## Features

- **Alpine Linux** - Lightweight base (~169MB)
- **dumb-init** - Proper signal handling and zombie process reaping
- **Supervisor** - Process management with logging
- **User/Group Mapping** - Run as any UID:GID via docker-compose user: directive
- **TZ Support** - Configurable timezone

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TZ` | UTC | Timezone (e.g., Europe/London, America/New_York) |

The `user:` directive in docker-compose handles UID/GID.

## Volumes

| Volume | Description |
|--------|-------------|
| `/config` | Persistent data directory (logs, configs, supervisord) |

The `/config` directory is created automatically on first run with proper permissions.

## Docker Compose Example

```yaml
services:
  alpine-base:
    image: ghcr.io/3n8/alpine-base-image:latest
    container_name: alpine-base
    restart: always
    user: "${PUID}:${PGID}"
    environment:
      - TZ=${TZ}
    volumes:
      - ${DOCKER_HOME}/alpine-base:/config
```

## How It Works

1. **Entry Point**: `dumb-init` handles signals (SIGTERM, SIGINT) for clean shutdown
2. **Init Script**: Sets up timezone, adjusts user/group IDs to match running user, sets permissions
3. **Supervisor**: Runs as the configured user to manage child processes
4. **Logging**: All output goes to `/config/supervisord.log` with timestamps

## Building

```bash
docker build -t ghcr.io/3n8/alpine-base-image:latest .
```

## Base for Child Images

This image is designed to be extended. Child images should:
- Use `FROM ghcr.io/3n8/alpine-base-image:latest`
- Copy scripts to `/usr/bin/init.sh` to customize startup
- Create subdirectories under `/config` for their data

## Image Details

- **Base**: Alpine Linux (latest)
- **Size**: ~169MB
- **User**: configurable via user: directive
- **Shell**: /bin/bash
