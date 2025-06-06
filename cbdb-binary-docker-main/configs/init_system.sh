#!/bin/bash
## ======================================================================
## Container initialization script
## ======================================================================

## Start SSH daemon and setup for ssh access
/usr/sbin/sshd

rm -rf /run/nologin

# ## Set gpadmin ownership - Clouberry install directory and supporting
# ## cluster creation files.
mkdir -p /data0/database/master /data0/database/primary /data0/database/mirror
chown -R gpadmin.gpadmin /usr/local/cloudberry-db \
                         /tmp/gpinitsystem_singlenode \
                         /tmp/gpinitsystem_multinode \
                         /tmp/gpinitsystem_multinode_mirrorless \
                         /tmp/gpdb-hosts \
                         /tmp/multinode-gpinit-hosts \
                         /data0

# # Allow passwordless ssh access
su gpadmin -l \
           -c "rm -rf /home/gpadmin/.ssh/; \
               mkdir -p /home/gpadmin/.ssh; chmod 700 /home/gpadmin/.ssh; \
               ssh-keygen -t rsa -b 4096 -C gpadmin -f /home/gpadmin/.ssh/id_rsa -P \"\" > /dev/null 2>&1; \
               cat /home/gpadmin/.ssh/id_rsa.pub >> /home/gpadmin/.ssh/authorized_keys; \
               chmod 600 /home/gpadmin/.ssh/authorized_keys; \
               ssh-keyscan -t rsa mdw > /home/gpadmin/.ssh/known_hosts;"

# Initialize single node Cloudberry cluster
if [[ $MULTINODE != "true" && $HOSTNAME == "mdw" ]]; then
  su gpadmin -l \
             -c "gpinitsystem -a \
                            -c /tmp/gpinitsystem_singlenode \
                            -h /tmp/gpdb-hosts \
                            --max_connections=100"
# Initialize multi node Cloudberry cluster
elif [[ $MULTINODE == "true" && $HOSTNAME == "mdw" ]]; then

  # 切换到 gpadmin 用户并复制 SSH 密钥  
  su gpadmin -l -c "  
    sshpass -p 'Hashdata@123' ssh-copy-id -o StrictHostKeyChecking=no sdw1;  
    sshpass -p 'Hashdata@123' ssh-copy-id -o StrictHostKeyChecking=no sdw2;  
    sshpass -p 'Hashdata@123' ssh-copy-id -o StrictHostKeyChecking=no smdw;  
  "  
  
  # 初始化 Greenplum 数据库系统  
  if [[ $MIRRORLESS != "true" ]]; then
    su gpadmin -l -c "  
      gpinitsystem -a -c /tmp/gpinitsystem_multinode -h /tmp/multinode-gpinit-hosts --max_connections=100;  
      "
    # 配置备用主机（假设这是必要的）  
    su gpadmin -l -c "  
      gpinitstandby -s smdw -a;  
      "
    printf "sdw1\nsdw2\n" >> /tmp/gpdb-hosts

  else
    su gpadmin -l -c "  
      sshpass -p 'Hashdata@123' ssh-copy-id -o StrictHostKeyChecking=no sdw3; 
      sshpass -p 'Hashdata@123' ssh-copy-id -o StrictHostKeyChecking=no sdw4; 
     "  
    su gpadmin -l -c "  
      gpinitsystem -a -c /tmp/gpinitsystem_multinode_mirrorless -h /tmp/mirrorless-gpinit-hosts --max_connections=100;  
    "
    printf "sdw1\nsdw2\nsdw3\nsdw4\n" >> /tmp/gpdb-hosts
    
  fi 
fi

if [ $HOSTNAME == "mdw" ]; then
     ## Allow any host access the Cloudberry Cluster
     su gpadmin -l \
               -c "echo 'host all all 0.0.0.0/0 trust' >> /data0/database/master/gpseg-1/pg_hba.conf; \
                    gpstop -u"

     su gpadmin -l \
               -c "psql -d template1 \
                         -c \"ALTER USER gpadmin PASSWORD 'Hashdata@123'\""

     cat <<-'EOF'

======================================================================
  ____ _                 _ _                            ____  ____
 / ___| | ___  _   _  __| | |__   ___ _ __ _ __ _   _  |  _ \| __ )
| |   | |/ _ \| | | |/ _` | '_ \ / _ \ '__| '__| | | | | | | |  _ \
| |___| | (_) | |_| | (_| | |_) |  __/ |  | |  | |_| | | |_| | |_) |
 \____|_|\___/ \__,_|\__,_|_.__/ \___|_|  |_|   \__, | |____/|____/
                                                |___/
======================================================================
EOF

     cat <<-'EOF'

======================================================================
Sandbox: Cloudberry Database Cluster details
======================================================================

EOF

     echo "Current time: $(date)"
     source /etc/os-release
     echo "OS Version: ${NAME} ${VERSION}"

     ## Set gpadmin password, display version and cluster configuration
     su gpadmin -l \
               -c "psql -P pager=off -d template1 \
                         -c \"SELECT VERSION()\"; \
                    psql -P pager=off -d template1 \
                         -c \"SELECT * FROM gp_segment_configuration ORDER BY dbid\"; \
                    psql -P pager=off -d template1 \
                         -c \"SHOW optimizer\""
fi

echo """
===========================
=  DEPLOYMENT SUCCESSFUL  =
===========================
"""

/bin/bash
