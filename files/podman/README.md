# Container startup

`podman.yml` installs `start-containers.sh` and runs it from
`podman-restart.service`.

The script starts databases, core services, the reverse proxy, then remaining
containers eligible for automatic startup. Startup order and delays are defined
in the script.

Shutdown stops the configured application clients before the remaining containers.
