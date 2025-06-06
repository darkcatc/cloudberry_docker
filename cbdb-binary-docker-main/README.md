# Cloudberry-binary-docker

Dockerfile for HashData Cloudberry env. 

This repo contains scripts to deploy HashData Cloudberry Database in docker containers for test purpose.

This image will download rpm for Cloudberry which runs on both arm and x86 chips. 

Current version includes will use Cloudberry 1.6.0.


Deploy steps:

1. Install Docker Desktop from https://www.docker.com/
2. Download this repo
3. execute run_x86.sh or run_arm.sh (On ARM chips)

Currently CentOS 7 and CentOS 9 are included for both single node / multiple nodes deployment. 

For single node installation both x86 and arm chips are supported.

Executed following commands for different OS / chips:

run_centos9_x86.sh 

run_centos9_arm.sh

run_centos7_x86.sh

run_centos7_arm.sh

For example to deploy a single node cluster with Centos 7 on x86 chips:

```
unzip Cloudberry-binary-docker.zip
cd Cloudberry-binary-docker
./run_centos7_x86.sh
[root@10-13-9-198 Cloudberry-binary-docker]# sh run_centos7_x86.sh
[+] Building 4.1s (14/14) FINISHED                                                                                                                                  docker:default
 => [internal] load build definition from Cloudberry_centos7_x86                                                                                                               0.1s
 => => transferring dockerfile: 2.53kB                                                                                                                                        0.0s
 => [internal] load metadata for docker.m.daocloud.io/centos:7.9.2009                                                                                                         3.6s
 => [internal] load .dockerignore                                                                                                                                             0.0s
 => => transferring context: 2B                                                                                                                                               0.0s
 => [1/9] FROM docker.m.daocloud.io/centos:7.9.2009@sha256:be65f488b7764ad3638f236b7b515b3678369a5124c47b8d32916d6487418ea4                                                   0.0s
 => [internal] load build context                                                                                                                                             0.0s
 => => transferring context: 806B                                                                                                                                             0.0s
 => CACHED [2/9] RUN     curl -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.huaweicloud.com/repository/conf/CentOS-7-anon.repo         && yum clean all         && yu  0.0s
 => CACHED [3/9] RUN     echo root:Hashdata@123 | chpasswd         && yum install -y epel-release                                                                             0.0s
 => CACHED [4/9] RUN     yum install -y apr apr-util bash bzip2 curl iproute krb5-devel libcgroup-tools libcurl libevent libuuid libuv libxml2 libyaml libzstd openldap open  0.0s
 => CACHED [5/9] RUN     yum install -y git passwd wget sudo net-tools sshpass                                                                                                0.0s
 => CACHED [6/9] RUN     wget https://cbdb-repository-2.obs.cn-north-4.myhuaweicloud.com/cbdb/centos7/x86_64/release/1.x/rpms/hashdata-Cloudberry-1.6.0-1.el7.x86_64-79708-re  0.0s
 => CACHED [7/9] RUN     yum install -y /tmp/hashdata-Cloudberry-release.rpm                                                                                                   0.0s
 => CACHED [8/9] COPY ./configs/* /tmp/                                                                                                                                       0.0s
 => CACHED [9/9] RUN     cat /tmp/sysctl.conf.add >> /etc/sysctl.conf         && cat /tmp/limits.conf.add >> /etc/security/limits.conf         && cat /usr/share/zoneinfo/As  0.0s
 => exporting to image                                                                                                                                                        0.0s
 => => exporting layers                                                                                                                                                       0.0s
 => => writing image sha256:553a78e944566a5038c354ba30508553ce6eaa37d9c79b8c5941870992ec021f                                                                                  0.0s
 => => naming to docker.io/library/Cloudberry:centos7                                                                                                                          0.0s
4a4246e4ce817014ef409b7a4afa155736dc2617e8d452e58d334fd6d44ec4dc
```

To use:

Find out the docker container id:
```
[root@10-13-9-198 Cloudberry-binary-docker]# docker ps
CONTAINER ID   IMAGE               COMMAND                  CREATED         STATUS        PORTS                                                                                              NAMES
4a4246e4ce81   Cloudberry:centos7   "bash -c /tmp/init_s…"   2 seconds ago   Up 1 second   22/tcp, 0.0.0.0:15432->5432/tcp, :::15432->5432/tcp, 0.0.0.0:17788->7788/tcp, :::17788->7788/tcp   wonderful_chatterjee
```

Log into docker container:
```
[root@10-13-9-198 ~]# docker exec -it 4a4246e4ce81 /bin/bash
[root@mdw /]# su - gpadmin
Last login: Tue Aug 13 17:06:53 CST 2024 on pts/0
[gpadmin@mdw ~]$ psql
psql (14.4, server 14.4)
Type "help" for help.

gpadmin=# select version();
                                                                                                                          version

-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------
 PostgreSQL 14.4 (Cloudberry Database 1.6.0 build 79708 commit:81b10d5c) (HashData Cloudberry 1.6.0 build 79708 commit:81b10d5c) on x86_64-pc-linux-gnu, compiled by gcc (GCC) 10.2.
1 20210130 (Red Hat 10.2.1-11), 64-bit compiled on Jul 12 2024 10:50:45
(1 row)

gpadmin=# select * from gp_segment_configuration;
 dbid | content | role | preferred_role | mode | status | port  | hostname | address |            datadir             | warehouseid
------+---------+------+----------------+------+--------+-------+----------+---------+--------------------------------+-------------
    1 |      -1 | p    | p              | n    | u      |  5432 | mdw      | mdw     | /data0/database/master/gpseg-1 |           0
    2 |       0 | p    | p              | n    | u      | 40000 | mdw      | mdw     | /data0/database/primary/gpseg0 |           0
    3 |       1 | p    | p              | n    | u      | 40001 | mdw      | mdw     | /data0/database/primary/gpseg1 |           0
(3 rows)

```

For multiple nodes installation only x86 chips are supported for now.

Executed following commands for different OS:

run_centos7_x86_multinodes.sh

run_centos9_x86_multinodes.sh

For example to deploy multiple nodes cluster with Centos 9 on x86 chips:

```
[root@10-13-9-198 Cloudberry-binary-docker]# sh run_centos9_x86_multinodes.sh
[+] Building 375.1s (13/13) FINISHED                                                                                                                                docker:default
 => [internal] load build definition from Cloudberry_centos9_x86                                                                                                               0.1s
 => => transferring dockerfile: 2.31kB                                                                                                                                        0.0s
 => [internal] load metadata for quay.io/centos/centos:stream9                                                                                                                1.6s
 => [internal] load .dockerignore                                                                                                                                             0.0s
 => => transferring context: 2B                                                                                                                                               0.0s
 => CACHED [1/8] FROM quay.io/centos/centos:stream9@sha256:dfa9d27873b0bff10df898b3bee4125b5c952dbaebe877ded15ee889b379d6c4                                                   0.0s
 => [internal] load build context                                                                                                                                             0.0s
 => => transferring context: 806B                                                                                                                                             0.0s
 => [2/8] RUN     echo root:Hashdata@123 | chpasswd         && yum install -y epel-release                                                                                   21.3s
 => [3/8] RUN     yum install --allowerasing -y apr apr-util bash bzip2 curl iproute krb5-devel libcurl libevent libuuid libuv libxml2 libyaml libzstd openldap openssh ope  68.1s
 => [4/8] RUN     yum install -y hostname iputils git passwd wget sudo net-tools sshpass procps                                                                               8.0s
 => [5/8] RUN     wget http://cbdb-repository-2.obs.cn-north-4.myhuaweicloud.com/cbdb/centos9/x86_64/dev/1.x/rpms/hashdata-Cloudberry-1.6.0-1.el9.x86_64-79799-release.rpm -  27.5s
 => [6/8] RUN     yum install -y /tmp/hashdata-Cloudberry-release.rpm                                                                                                        168.0s
 => [7/8] COPY ./configs/* /tmp/                                                                                                                                              0.3s
 => [8/8] RUN     cat /tmp/sysctl.conf.add >> /etc/sysctl.conf         && cat /tmp/limits.conf.add >> /etc/security/limits.conf         && cat /usr/share/zoneinfo/Asia/Sha  35.3s
 => exporting to image                                                                                                                                                       43.8s
 => => exporting layers                                                                                                                                                      43.6s
 => => writing image sha256:9689e719b9112d1c53e03a664d1428c26cd31657264be6fce039f2165f0e0948                                                                                  0.0s
 => => naming to docker.io/library/Cloudberry:centos9                                                                                                                          0.0s
[+] Running 5/5
 ✔ Network cbdb-interconnect  Created                                                                                                                                         0.3s
 ✔ Container cbdb-mdw         Started                                                                                                                                         1.1s
 ✔ Container cbdb-sdw1        Started                                                                                                                                         1.1s
 ✔ Container cbdb-sdw2        Started                                                                                                                                         1.1s
 ✔ Container cbdb-smdw        Started                                                                                                                                         1.1s
```

Find out the coordinator container id:
```
[root@10-13-9-198 ~]# docker ps
CONTAINER ID   IMAGE               COMMAND                  CREATED         STATUS         PORTS                                                 NAMES
737c962d6540   Cloudberry:centos7   "bash -c /tmp/init_s…"   8 seconds ago   Up 7 seconds   22/tcp, 0.0.0.0:15433->5432/tcp, :::15433->5432/tcp   cbdb-mdw
10e9a44984b0   Cloudberry:centos7   "bash -c /tmp/init_s…"   8 seconds ago   Up 7 seconds   22/tcp, 5432/tcp                                      cbdb-smdw
928c656a0af7   Cloudberry:centos7   "bash -c /tmp/init_s…"   8 seconds ago   Up 7 seconds   22/tcp, 5432/tcp                                      cbdb-sdw1
ff875a1cdbbc   Cloudberry:centos7   "bash -c /tmp/init_s…"   8 seconds ago   Up 7 seconds   22/tcp, 5432/tcp                                      cbdb-sdw2

```

Log into coordinator container:
```
[root@10-13-9-198 ~]# docker exec -it 737c962d6540 /bin/bash
[root@mdw /]# su - gpadmin
Last login: Tue Aug 13 15:09:57 CST 2024 on pts/0

[gpadmin@mdw local]$ psql
psql (14.4, server 14.4)
Type "help" for help.

gpadmin=# select version();
                                                                                                                          version

-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------
 PostgreSQL 14.4 (Cloudberry Database 1.6.0 build 79708 commit:81b10d5c) (HashData Cloudberry 1.6.0 build 79708 commit:81b10d5c) on x86_64-pc-linux-gnu, compiled by gcc (GCC) 10.2.
1 20210130 (Red Hat 10.2.1-11), 64-bit compiled on Jul 12 2024 10:50:45
(1 row)

gpadmin=# select * from gp_segment_configuration ;
 dbid | content | role | preferred_role | mode | status | port  | hostname | address |            datadir             | warehouseid
------+---------+------+----------------+------+--------+-------+----------+---------+--------------------------------+-------------
    1 |      -1 | p    | p              | n    | u      |  5432 | mdw      | mdw     | /data0/database/master/gpseg-1 |           0
    2 |       0 | p    | p              | n    | u      | 40000 | sdw1     | sdw1    | /data0/database/primary/gpseg0 |           0
    4 |       2 | p    | p              | n    | u      | 40000 | sdw2     | sdw2    | /data0/database/primary/gpseg2 |           0
    3 |       1 | p    | p              | n    | u      | 40001 | sdw1     | sdw1    | /data0/database/primary/gpseg1 |           0
    5 |       3 | p    | p              | n    | u      | 40001 | sdw2     | sdw2    | /data0/database/primary/gpseg3 |           0
    6 |       0 | m    | m              | n    | d      | 50000 | sdw2     | sdw2    | /data0/database/mirror/gpseg0  |           0
    7 |       1 | m    | m              | n    | d      | 50001 | sdw2     | sdw2    | /data0/database/mirror/gpseg1  |           0
    8 |       2 | m    | m              | n    | d      | 50000 | sdw1     | sdw1    | /data0/database/mirror/gpseg2  |           0
    9 |       3 | m    | m              | n    | d      | 50001 | sdw1     | sdw1    | /data0/database/mirror/gpseg3  |           0
(9 rows)

```

Now enjoy your Cloudberry cluster for testing!