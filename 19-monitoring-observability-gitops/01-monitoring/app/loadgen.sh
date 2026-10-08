#!/bin/sh
# Steady synthetic traffic: mostly reads, some writes.
while true; do
  wget -qO- http://app:8000/api/orders >/dev/null 2>&1
  wget -qO- http://app:8000/api/orders >/dev/null 2>&1
  wget -qO- --post-data='{}' --header='Content-Type: application/json' http://app:8000/api/orders >/dev/null 2>&1
  sleep 0.2
done
