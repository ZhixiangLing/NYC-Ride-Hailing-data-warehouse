# 纽约网约车离线数仓项目：需求说明书

Oct 22, 2026 · @Ling

## 1. 项目背景

你扮演一家网约车平台数据团队的数据开发工程师：用 Spark + Hive 把纽约网约车的原始行程数据，建成 ODS → DWD/DIM → DWS → ADS 的分层离线数仓，并产出能回答四个业务问题的指标表。

**现状（你要解决的问题）：** 原始行程数据按月发布，每月一个大文件。运营、财务、调度团队各自从原始文件取数，口径不一样。比如"乘客等待时长"，有人从叫车算到司机到达，有人算到上车；"订单收入"有人含小费，有人不含。同样的汇总被反复计算，各部门的数字对不上。

**你的任务：** 统一清洗规则和指标口径，建立公共维度表和明细事实表，沉淀可复用的汇总表，产出业务直接能用的指标表。整条链路要能按天调度、能重跑、有数据质量校验。

**ADS 层最终要回答的业务问题：**

1. **供需：** 每个区域、每个时段的叫车量是多少？哪些区域和时段最繁忙？
2. **服务体验：** 乘客从叫车到上车要等多久？哪些区域、哪些时段等得最久？
3. **平台经济：** 乘客支付的钱里，司机拿到多少？平台抽成率在不同平台、区域、时段之间有什么差异？
4. **机场订单：** 往返机场的订单和市内订单相比，里程、收入、等待时长有什么不同？

**面试时的故事线：** 你在 Göteborg Energi 做的是实时流处理（Flink）。这个项目让你补上离线数仓这一侧。简历上，论文和实习代表实时处理，这个项目代表离线数仓，数据开发的两条主线你都有亲手做过的经历。

## 2. 数据来源

数据全部来自纽约出租车与豪华轿车委员会（TLC）的官方公开数据，免费下载，不需要自己造：主数据是网约车大平台（Uber、Lyft 等）的行程记录，按月以 Parquet 格式发布，入口在 [TLC Trip Record Data](https://www.nyc.gov/site/tlc/about/tlc-trip-record-data.page) 页面。

**要下载的文件：**

| 文件 | 内容 | 进入哪一层 |
| --- | --- | --- |
| High Volume FHV Trip Records（按月，Parquet） | 每行一次行程，核心事实数据 | ODS → DWD 行程事实表 |
| Taxi Zone Lookup Table（CSV，同一页面） | 区域 ID 对应的行政区、区域名、服务区类型 | ODS → 区域维度 |
| 官方数据字典 PDF | 字段定义 | 不入库，建模时对照 |

**核心字段（摘自[官方数据字典](https://www.nyc.gov/assets/tlc/downloads/pdf/data_dictionary_trip_records_hvfhs.pdf)）：**

| 类别 | 字段 | 用途 |
| --- | --- | --- |
| 平台 | hvfhs\_license\_num（HV0002 Juno、HV0003 Uber、HV0004 Via、HV0005 Lyft） | 平台维度 |
| 生命周期时间 | request\_datetime、on\_scene\_datetime、pickup\_datetime、dropoff\_datetime | 累积快照事实、等待时长 |
| 地点 | PULocationID、DOLocationID | 关联区域维度 |
| 里程时长 | trip\_miles、trip\_time（秒） | 行程度量 |
| 费用 | base\_passenger\_fare、tolls、bcf、sales\_tax、congestion\_surcharge、airport\_fee、tips、cbd\_congestion\_fee | 乘客支付总额 |
| 司机收入 | driver\_pay（不含过路费和小费，已扣除平台佣金、附加费和税） | 平台抽成率 |
| 服务标记 | shared\_request\_flag、shared\_match\_flag、access\_a\_ride\_flag、wav\_request\_flag、wav\_match\_flag | 拼车、无障碍分析 |

**三个必须提前知道的数据坑（它们正是这个项目的学习价值）：**

1. **司机到达时间只对无障碍车辆有值。** 数据字典写明 on\_scene\_datetime 仅适用于无障碍车辆。所以业务问题 2 的"等待时长"统一口径定为"叫车到上车"（request → pickup），这是你要写进指标文档的口径决策。
2. **字段随时间变化。** cbd\_congestion\_fee 是 2025 年 1 月 5 日起才有的收费。跨年份读取时会遇到 schema 不一致，ODS 层要处理 schema 合并。
3. **数据准确性不保证。** TLC 明确说明 FHV 行程数据由各平台提交，TLC 无法保证其准确性和完整性。负数费用、零里程、时间倒挂（下车早于上车）、跨月时间戳都要在 DWD 层识别和处理。

**规模建议：** 先只用 1 个月的数据跑通全流程，再扩到 6–12 个月。具体行数下载后自己统计，写进 ODS 层的验收记录里。月份多了以后，Spark 的 shuffle、倾斜、小文件问题才会真实出现，这正是后面实验需要的。

## 3. 技术栈与环境

技术栈按国内数据开发 JD 的主流组合来选：HDFS + YARN + Hive Metastore + Spark SQL + DolphinScheduler。原则是每个组件都要有真实的用途，面试官问"为什么用它"时你答得上来。

**一句话分工：** HDFS 负责存文件；Hive Metastore 负责记住"有哪些表、表结构是什么、每个分区的文件在 HDFS 哪个目录"；YARN 负责给计算任务分配 CPU 和内存；Spark 负责真正执行 SQL 计算。

| 组件 | 在项目里做什么 | 你会学到 / 面试常问 |
| --- | --- | --- |
| HDFS（伪分布式） | 存放所有分层表的数据文件 | 块、副本、NameNode 元数据；小文件为什么有害 |
| YARN | Spark 作业的资源调度 | Spark on YARN 的提交流程；Driver 和 Executor 的资源配置 |
| Hive Metastore（PostgreSQL 做后端） | 管理库、表、分区的元数据 | 内部表与外部表；分区表；动态分区 |
| Spark 3.x（Spark SQL 为主，PySpark 补充） | 所有层的 ETL 计算 | shuffle、宽窄依赖、join 策略、AQE、数据倾斜 |
| ORC / Parquet + Snappy | 数仓表的存储格式 | 列式存储、谓词下推、压缩取舍 |
| DolphinScheduler（或 Airflow） | 按天调度、任务依赖、失败重跑 | DAG 依赖、补数据（回填历史分区）、幂等 |
| SQL 数据质量校验 | 行数、主键唯一、空值率、取值范围检查，失败阻断下游 | 数据质量怎么保证 |
| Git + GitHub | 代码、建模文档、实验记录 | 面试官可以直接看你的仓库 |

**故意不用的组件：** Flume、Sqoop、DataX、Kylin、Presto 等。原因是你的数据源是官方发布的文件，不是业务数据库或日志服务器，硬加这些组件就是凑数。这也是你和跟课项目最明显的区别：技术栈短，但每一个都讲得清楚为什么用。

**环境方案（M 系列芯片 + 16GB 内存）：**

阶段 0 的数据探查在本机用 PySpark 本地模式完成；从阶段 1 起，在 Docker 里搭一套伪分布式环境，之后所有表都建在这套环境上。

| 容器 | 镜像 | 运行的服务 | 分配内存 |
| --- | --- | --- | --- |
| hadoop | openeuler/hadoop:3.4.1（支持 M 芯片） | HDFS（NameNode、DataNode）、YARN（ResourceManager、NodeManager），另装 Spark 3.5 作为提交客户端 | 约 8GB |
| metastore | apache/hive 的 standalone-metastore 4.x 镜像（支持 M 芯片） | Hive Metastore 服务 | 约 1GB |
| postgres | postgres 官方镜像 | Metastore 背后的元数据库 | 约 0.5GB |

- **为什么不用 Apache 官方的 Hadoop 镜像：** apache/hadoop 镜像只提供 Intel（amd64）版本，在 M 芯片上要模拟运行，速度明显变慢。
- **元数据库为什么用 PostgreSQL：** 企业里更常见的是 MySQL，两者作用完全一样。这里用 PostgreSQL，是因为 Hive 官方的 Docker 示例就是这套组合，配置最省事。
- **作业怎么提交：** 每层的 ETL 写成 .sql 文件，在 hadoop 容器里用 `spark-sql --master yarn -f 文件名.sql` 提交。这正是企业里最常见的离线作业形态：调度系统每天按顺序执行一批 SQL 脚本。PySpark 只用于阶段 0 的数据探查。
- **内存怎么分：** Docker Desktop（或更轻量的 OrbStack）总共分配约 10GB，剩下约 6GB 留给 macOS。YARN 可用内存设为约 6GB，跑 2 个 Executor，每个约 2GB；一次只处理一个月的数据。
- **DolphinScheduler：** 放到阶段 5 再加，到时根据内存情况评估镜像和资源。

## 4. 分层架构与表设计

数据自上而下经过 ODS → DWD/DIM → DWS → ADS 四层加工，每一层都由调度系统触发、经过质量校验后才放行下游。

（架构图无法导出为文字，请在线上需求文档中查看。）

**表清单（起点方案，阶段 1 由你自己定稿）：**

| 表名 | 层 | 粒度 | 主要内容 | 分区 |
| --- | --- | --- | --- | --- |
| ods\_hvfhv\_trip | ODS | 一次行程一行（原样） | 官方全部字段 | 按文件月份 |
| ods\_taxi\_zone | ODS | 一个区域一行 | 原始区域对照表 | 不分区 |
| dim\_zone | DIM | 一个区域一行 | 行政区、区域名、服务区类型、是否机场 | 不分区 |
| dim\_platform | DIM | 一个平台牌照一行 | 牌照号对应的平台名 | 不分区 |
| dim\_date | DIM | 一天一行 | 年、月、日、星期、是否周末 | 不分区 |
| dwd\_trip\_detail | DWD | 一次行程一行 | 清洗后的四个时间点、等待时长、里程、各项费用、乘客支付总额、司机收入 | 上车日期 |
| dwd\_trip\_anomaly | DWD | 一条异常记录一行 | 异常行程及命中的清洗规则 | 上车日期 |
| dws\_trip\_zone\_hour | DWS | 区域 × 小时 | 叫车量、平均等待时长、乘客支付总额、司机收入 | 日期 |
| dws\_trip\_platform\_day | DWS | 平台 × 天 | 行程数、乘客支付总额、司机收入 | 日期 |
| ads\_supply\_demand 等四张 | ADS | 按各自业务问题 | 第 1 节四个业务问题的指标 | 日期 |

**一个面试常问的建模点：** 行程表里有叫车、到达、上车、下车四个里程碑时间，结构上很像累积快照事实表。但这份数据是行程结束后一次性提交的，记录不会再更新，所以在你的项目里它实际是一张带里程碑时间的事务事实表。面试时把这个区别讲清楚，并说明如果在真实平台里订单状态是逐步更新的，你会怎样把它建成累积快照表，这比直接套术语有说服力得多。

## 5. Spark 对比实验

每个 Spark 核心概念都要亲手"制造一次问题、再解决它"，并留下前后对比的数字。这些数字就是你简历上可以写、面试时经得起追问的内容。

| 实验 | 怎么做 | 看什么 | 对应的面试问题 |
| --- | --- | --- | --- |
| Broadcast Join vs Sort-Merge Join | 行程事实表关联区域维度表；把 spark.sql.autoBroadcastJoinThreshold 设为 -1 跑一次，再恢复默认跑一次 | Spark UI 里的 stage 数、shuffle 读写量、耗时 | Spark 有哪些 join 策略，什么时候用哪种 |
| 数据倾斜 | 先统计各平台、各区域的行程数分布，找出最不均匀的 key；用它做 group by 或 join，观察长尾 task；再分别用 AQE 倾斜优化和加盐解决 | 各 task 耗时分布、最慢 task 与中位数的差距 | 数据倾斜怎么发现、怎么解决 |
| 小文件问题 | 按天分区写 DWD，不做任何控制，统计文件数；再用 repartition / coalesce / AQE 合并分区重写 | 每个分区的文件数和平均大小、下游读取耗时 | 小文件为什么有害，怎么治理 |
| 分区裁剪与谓词下推 | 同一个查询，带 dt 分区条件和不带各跑一次；对比 EXPLAIN 输出 | 执行计划里的 PartitionFilters / PushedFilters、扫描文件数 | 分区表怎么设计，查询为什么快 |
| 存储格式对比 | 同一份 DWD 数据分别存为 ORC、Parquet、CSV，跑同一个查询 | 存储大小、查询耗时 | 列式存储的优势，ORC 和 Parquet 怎么选 |
| 缓存复用 | 从同一张 DWS 表计算多张 ADS 表，对比 cache 和不 cache | 总耗时、是否重复扫描 | cache 和 persist 的区别，什么时候该用 |

**每个实验的记录要求：** 数据量（几个月、多少行）、关键配置、优化前后的数字、Spark UI 截图、两三句结论。

**注意：** 单机环境的绝对耗时没有意义，简历和面试里只说相对变化（比如 shuffle 量减少多少、文件数从多少降到多少），并说明是在什么数据量和环境下测的。

## 6. 阶段计划与验收标准

全程约 4 周，分 8 个阶段；做完阶段 4 就有一个可以讲的最小完整版本。每个阶段的验收项做完就打勾，没打勾的内容不写进简历。

**阶段 0：本地数据探查（2–3 天）。** 学会：数据探查，也就是建模之前先摸清数据。

- [ ] 本地 PySpark 能读取一个月的行程数据和区域表
- [ ] 写出数据探查笔记：总行数、各字段空值率、异常值数量（负数费用、零里程、时间倒挂、跨月时间戳）
- [ ] 统计各平台、各区域的行程数分布，为倾斜实验找 key

**阶段 1：建模设计 + 搭建集群（3–5 天，两件事交替进行）。** 学会：业务过程、粒度、维度、事实表类型、指标口径；HDFS、YARN、Hive Metastore 的实际用法。

- [ ] 画出总线矩阵：业务过程 × 维度
- [ ] 每张表写清楚粒度、主键、分区键
- [ ] 写指标口径文档：每个指标拆成原子指标 + 业务限定 + 统计周期 + 统计粒度
- [ ] 设计交给 Claude 按面试官视角评审
- [ ] Docker 中 HDFS、YARN、Hive Metastore 全部跑通，各自的网页界面能打开
- [ ] 在集群上用 spark-sql --master yarn 建一张测试表并查询成功

**阶段 2：ODS + DIM（3 天，从这里开始所有表都建在集群上）。** 学会：外部表、分区表、维度表设计。

- [ ] ODS 原样落地，按日期分区，处理跨月份的 schema 差异
- [ ] 建好区域维度、平台维度、日期维度（日期维度自己生成）

**阶段 3：DWD（3–4 天）。** 学会：清洗规则、去重、异常数据隔离、事实表设计。

- [ ] 行程明细事实表，粒度为"一次行程一行"
- [ ] 每条清洗规则有数据依据，并统计每条规则过滤了多少行
- [ ] 异常数据写入单独的隔离表，而不是直接丢弃

**阶段 4：DWS + ADS（3–4 天）。** 学会：汇总层复用、宽表、指标计算。

- [ ] 按"区域 × 小时""平台 × 天"等粒度建汇总表
- [ ] 四个业务问题各有一张 ADS 表，结果能用一两句话解释

**阶段 5：调度 + 数据质量（3–4 天）。** 学会：调度依赖、幂等、补数据。

- [ ] DolphinScheduler 配好按天的任务依赖
- [ ] 数据质量校验失败时阻断下游任务
- [ ] 成功回填至少 3 个月的历史分区，且重跑结果一致

**阶段 6：Spark 实验（3–4 天）。** 学会：第 5 节的全部概念。

- [ ] 第 5 节六个实验全部完成，并有记录

**阶段 7：文档与简历（1–2 天）。**

- [ ] README、架构图、建模文档、实验报告整理完成
- [ ] 按第 8 节更新简历

## 7. 分工

代码、SQL 和设计决策全部由你自己完成；Claude 负责评审、讲解和排错。原因很简单：面试官会顺着项目一路问到原理，不是你亲手写的东西，你讲不深。

| 事项 | 你 | Claude |
| --- | --- | --- |
| 建模设计（粒度、维度、口径） | 先自己设计 | 按面试官视角评审、追问 |
| 代码和 SQL | 全部自己写 | 卡住时给思路，不直接给整段答案；做代码 review |
| 环境搭建 | 自己动手 | 帮你看报错日志 |
| 概念学习 | 遇到不懂的就问 | 结合你项目里的具体场景讲解 |
| 实验 | 自己跑、自己记录数字 | 帮你解读 Spark UI 和执行计划 |
| 面试准备 | 自己讲项目 | 模拟面试、追问薄弱点 |

**一条硬规则：** 如果某段代码参考了 Claude 给的思路，你必须能逐行解释它在做什么、为什么这样写，否则不放进仓库。

**工作方式：** 每完成一个阶段，把设计或代码贴过来，我按面试官的方式追问；你答不上来的地方，就是下一步要补的知识点。

## 8. 最终交付物与简历写法

最终交付物是一个公开的 GitHub 仓库，加上简历里的一个项目条目。仓库要让面试官五分钟内看懂你做了什么、为什么这样做。

**仓库结构：**

- README：项目背景、架构图、各层表清单、如何运行
- docs/：建模文档（总线矩阵、每张表的粒度）、指标口径文档、清洗规则及过滤统计、数据质量规则
- experiments/：六个 Spark 实验的记录和截图
- 代码按层组织：ods/、dim/、dwd/、dws/、ads/、dq/（数据质量）、scheduler/（调度配置）

**简历条目模板（英文；方括号里只能填你实测的真实数字，没有就删掉那半句）：**

*Ride-Hailing Offline Data Warehouse (Personal Project) — Spark SQL, Hive, HDFS/YARN, DolphinScheduler*

- Built a layered offline data warehouse (ODS/DWD/DIM/DWS/ADS) on Spark SQL and Hive Metastore for NYC ride-hailing trip records (\[N\] months, \[X\]M rows).
- Designed dimensional models with a trip-level fact table and zone, platform and date dimensions; defined consistent metrics for wait time, trip revenue and platform take rate.
- Implemented data cleaning and quality checks that isolated \[X\]% anomalous records (negative fares, zero-distance trips, invalid timestamps) and blocked downstream jobs on failure.
- Tuned Spark jobs with broadcast joins, AQE skew handling and small-file compaction, reducing \[shuffle volume / file count\] from \[A\] to \[B\].
- Orchestrated daily pipelines with DolphinScheduler, including dependency management and idempotent backfill of historical partitions.

**写简历时的注意事项：**

- 标题注明是个人项目（Personal Project），不写"生产环境""日均处理"之类的说法，因为数据是历史文件，一问就穿。
- 做完阶段 4 和至少两个实验后再写进简历；没完成的部分不写。
- 这个项目上简历后，替换掉原来的 ASketch 项目，让简历同时覆盖实时（论文和实习）和离线（本项目）两条线。
