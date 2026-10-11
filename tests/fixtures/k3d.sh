#!/usr/bin/env bash

printf 'unexpected k3d invocation: %s\n' "$*" >&2
exit 1
