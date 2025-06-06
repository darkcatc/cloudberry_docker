#! /bin/bash

docker build -f cbdb_centos9_arm -t cbdb:centos9_arm .
#! docker run -ti -d -v /sys/fs/cgroup:/sys/fs/cgroup:ro -p 22:22 -p 5432:5432 -h mdw cbdb:centos8
docker run --privileged -ti -d -v /sys/fs/cgroup:/sys/fs/cgroup:ro -p 17788:7788 -p 15432:5432 -h mdw cbdb:centos9_arm