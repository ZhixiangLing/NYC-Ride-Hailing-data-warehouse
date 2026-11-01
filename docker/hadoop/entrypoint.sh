#!/bin/bash
# 容器启动时执行的脚本：依次启动 HDFS 和 YARN 的各个服务
set -e

# 1. 第一次启动时格式化 NameNode（相当于给 HDFS "装文件系统"）。以后启动时数据已存在，跳过
if [ ! -d /data/hdfs/name/current ]; then
  echo ">>> 第一次启动，格式化 NameNode"
  hdfs namenode -format -nonInteractive
fi

# 2. 启动 HDFS：NameNode 管元数据，DataNode 存数据块
hdfs --daemon start namenode
hdfs --daemon start datanode

# 3. 启动 YARN：ResourceManager 统一分配资源，NodeManager 在本机上运行任务
yarn --daemon start resourcemanager
yarn --daemon start nodemanager

# 4. 等待 HDFS 退出安全模式（刚启动时 HDFS 只读，等数据块汇报完成）
hdfs dfsadmin -safemode wait

# 5. 创建常用目录
hdfs dfs -mkdir -p /user/hive/warehouse /tmp /spark
hdfs dfs -chmod -R 777 /user/hive/warehouse /tmp

# 6. 把 Spark 的依赖包上传到 HDFS 一次。否则每次提交作业都要重新上传约 300MB，启动很慢
if ! hdfs dfs -test -d /spark/jars; then
  echo ">>> 上传 Spark 依赖包到 HDFS（只在第一次启动时执行）"
  hdfs dfs -put ${SPARK_HOME}/jars /spark/
fi

echo ">>> Hadoop is ready"

# 7. 持续输出日志，让容器保持运行
tail -F ${HADOOP_HOME}/logs/*.log
