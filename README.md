# Zwavejs2MQTT from scratch!
[![Build Status](https://github.com/LANsible/docker-zwavejs2mqtt/actions/workflows/docker.yml/badge.svg)](https://github.com/LANsible/docker-zwavejs2mqtt/actions/workflows/docker.yml)
[![Docker Pulls](https://img.shields.io/docker/pulls/lansible/zwavejs2mqtt.svg)](https://hub.docker.com/r/lansible/zwavejs2mqtt)
[![Docker Version](https://img.shields.io/docker/v/lansible/zwavejs2mqtt.svg?sort=semver)](https://hub.docker.com/r/lansible/zwavejs2mqtt)
[![Docker Size/Layers](https://img.shields.io/docker/image-size/lansible/zwavejs2mqtt.svg?sort=semver)](https://hub.docker.com/r/lansible/zwavejs2mqtt)

## Why not use the official container?

Mostly since the upstream container want to write where the settings are stored. I want to keep the settings in a Kubernetes configmap and that makes the folder readonly and not writable.
I use a little patch to move the settings to their own location :)
Also this a super small container since Zwave2js2MQTT is build as a single binary and put into a FROM scratch container.
The container run as user 1000 with primary group 1000 and dailout(20) as secondary group for tty access.

## Test container with docker-compose

```
cd examples/compose
docker-compose up
```

### Building the container locally

You could build the container locally like this:

```bash
docker build . --tag lansible/zwavejs2mqtt:dev-amd64
```

Available architectures are what `lansible/nexe` supports:
https://hub.docker.com/r/lansible/nexe/tags

## Credits

* [zwave-js/zwavejs2mqtt](https://github.com/zwave-js/zwavejs2mqtt/)