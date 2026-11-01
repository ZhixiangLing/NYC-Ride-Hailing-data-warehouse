# 固定使用 Hive 4.0.0：
# Hive 4.0.1 删除了 Spark 3.5 内置的元数据客户端依赖的接口（get_table 等），
# 两者连接时会报 "Invalid method name"。4.0.0 仍保留这些接口。
FROM apache/hive:4.0.0

# 官方镜像不带 PostgreSQL 的 JDBC 驱动，这里从 Maven 中央仓库下载放进去
ADD --chmod=644 https://repo1.maven.org/maven2/org/postgresql/postgresql/42.5.1/postgresql-42.5.1.jar /opt/hive/lib/postgres.jar
