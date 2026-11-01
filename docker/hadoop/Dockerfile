# 基础镜像：Eclipse Temurin 官方 Java 11，同时提供 Intel 和 M 芯片（arm64）版本
FROM eclipse-temurin:11-jdk-jammy

# 下载源。如果下载很慢，可以在构建时换成别的 Apache 镜像站（路径结构相同即可）
ARG APACHE_MIRROR=https://archive.apache.org/dist

ENV HADOOP_VERSION=3.3.6 \
    SPARK_VERSION=3.5.5 \
    HADOOP_HOME=/opt/hadoop \
    SPARK_HOME=/opt/spark \
    HADOOP_CONF_DIR=/opt/hadoop/etc/hadoop
ENV PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$SPARK_HOME/bin

# Hadoop 3 默认不允许用 root 启动各个服务，这里显式声明允许（仅限本地学习环境）
ENV HDFS_NAMENODE_USER=root \
    HDFS_DATANODE_USER=root \
    HDFS_SECONDARYNAMENODE_USER=root \
    YARN_RESOURCEMANAGER_USER=root \
    YARN_NODEMANAGER_USER=root

RUN apt-get update \
 && apt-get install -y --no-install-recommends curl procps \
 && rm -rf /var/lib/apt/lists/*

# 下载并解压 Hadoop
RUN curl -fSL ${APACHE_MIRROR}/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz \
    | tar -xz -C /opt \
 && mv /opt/hadoop-${HADOOP_VERSION} ${HADOOP_HOME}

# 下载并解压 Spark（自带 Hive 支持，可直接使用 spark-sql）
RUN curl -fSL ${APACHE_MIRROR}/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop3.tgz \
    | tar -xz -C /opt \
 && mv /opt/spark-${SPARK_VERSION}-bin-hadoop3 ${SPARK_HOME}

# 告诉 Hadoop 的脚本 Java 装在哪里
RUN echo "export JAVA_HOME=${JAVA_HOME}" >> ${HADOOP_HOME}/etc/hadoop/hadoop-env.sh

# 放入我们自己的配置文件
COPY conf/hadoop/ ${HADOOP_HOME}/etc/hadoop/
COPY conf/spark/  ${SPARK_HOME}/conf/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
