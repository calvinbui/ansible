#!/bin/bash
unset INVOCATION_ID # Keep container monitors outside this startup service.
result=0

start() {
    podman start --all --filter should-start-on-boot=true "$@" || result=1
}

echo 'Starting databases'
start --filter 'name=-(postgres|mariadb|valkey|influxdb|mongodb|elasticsearch)$'
sleep 10

echo 'Starting NTP, Authelia, CrowdSec and EMQX'
start --filter 'name=^ntp$'
start --filter 'name=^authelia$'
start --filter 'name=^crowdsec$'
start --filter 'name=^emqx$'
sleep 30

echo 'Starting Traefik'
start --filter 'name=^traefik$'
sleep 5

echo 'Starting remaining containers'
start
exit "$result"
