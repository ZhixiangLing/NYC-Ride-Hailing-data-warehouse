# 模型设计文档

纽约网约车离线数仓项目（数据：NYC TLC High Volume FHV Trip Records）

## 1. 总体设计

- **业务过程：** 完成一次行程（TLC 只发布已完成的行程，叫车、派单、取消、支付等过程不在数据范围内）
- **模型结构：** 星型模型，一张事实表 + 四张维度表

### 1.1 总线矩阵

| 业务过程 | 日期 | 时段 | 上车区域 | 下车区域 | 平台 |
| --- | --- | --- | --- | --- | --- |
| 完成一次行程 | ✓ | ✓ | ✓ | ✓ | ✓ |

| 维度 | 需要的原因 |
| --- | --- |
| 日期 | 数据按天更新、按天分区，所有指标都要能按天查看 |
| 时段 | 业务问题 1、2、3 都要按时段分析 |
| 上车区域 | 业务问题 1、2、3 的"区域"指上车区域 |
| 下车区域 | 业务问题 4 判断机场订单需要下车区域（纽瓦克机场几乎只有下车） |
| 平台 | 业务问题 3 比较各平台的抽成率 |

## 2. 维度表

### 2.1 平台维度 dim_platform

- **粒度：** 一行 = 一个 TLC 网约车平台牌照
- **主键：** platform_code（自然键，来自行程数据的 hvfhs_license_num）
- **数据来源：** 人工维护（码表），依据 TLC 数据字典

| 字段名 | 类型 | 含义 | 示例 |
| --- | --- | --- | --- |
| platform_code | string | 平台牌照编号 | HV0003 |
| platform_name | string | 平台名称 | Uber |
| is_active | boolean | 是否仍在运营 | true |

**数据内容：** HV0002 Juno（已停运）、HV0003 Uber、HV0004 Via（已停运）、HV0005 Lyft

### 2.2 时段维度 dim_time_slot

- **粒度：** 一行 = 一天中的一个小时（共 24 行）
- **主键：** hour（0–23，对应 hour(pickup_datetime) 的返回值）
- **数据来源：** 人工维护（码表），依据探查阶段的 24 小时行程分布

| 字段名 | 类型 | 含义 | 示例 |
| --- | --- | --- | --- |
| hour | int | 小时，0–23 | 18 |
| slot_name | string | 时段名称 | 晚高峰 |
| is_peak | boolean | 是否高峰 | true |

**时段划分（依据 2024 年 12 月 24 小时分布，24 个小时不重不漏）：**

| 时段 | 小时 | 是否高峰 | 依据 |
| --- | --- | --- | --- |
| 深夜 | 0–5 | 否 | 全天最低，3 点约 31 万条 |
| 早晨 | 6 | 否 | 约 56 万条，处于上升阶段，低于全天平均 |
| 早高峰 | 7–9 | 是 | 第一个峰值，8 点约 100 万条 |
| 白天 | 10–16 | 否 | 平稳 |
| 晚高峰 | 17–20 | 是 | 全天最高，19 点约 125 万条 |
| 夜间 | 21–23 | 否 | 仍然较高，23 点约 101 万条 |

### 2.3 日期维度 dim_date

- **粒度：** 一行 = 一个自然日
- **主键：** date（格式 yyyy-MM-dd，与事实表的 dt 对应）
- **数据来源：** 用 SQL 按日期范围生成；节假日信息人工维护（美国节假日）
- **说明：** 日期维度必须连续完整，不从行程数据中提取，以免漏掉没有数据的日期

| 字段名 | 类型 | 含义 | 示例 |
| --- | --- | --- | --- |
| date | date | 日期 | 2024-12-25 |
| date_key | int | 整型日期 | 20241225 |
| year | int | 年 | 2024 |
| quarter | int | 季度 | 4 |
| month | int | 月 | 12 |
| week_of_year | int | 一年中的第几周（ISO 标准） | 52 |
| day_of_week | int | 星期几（1 = 周一） | 3 |
| day_name | string | 星期名称 | 周三 |
| is_weekend | boolean | 是否周末 | false |
| is_holiday | boolean | 是否美国节假日 | true |
| holiday_name | string | 节假日名称 | Christmas Day |
| is_workday | boolean | 是否工作日（非周末且非节假日） | false |

**注意：** week_of_year 采用 ISO 标准，年底年初可能归属下一年，例如 2024-12-30 属于 2025 年第 1 周。

### 2.4 区域维度 dim_zone

- **粒度：** 一行 = 一个 TLC 出租车区域
- **主键：** location_id（自然键，对应事实表的上车区域 ID 和下车区域 ID）
- **数据来源：** TLC 区域对照表 + 人工补充的机场和特殊区域标记
- **说明：** 事实表通过上车、下车两个区域 ID 分别关联本表（角色扮演维度）。层级为：纽约市 → 行政区（borough，每个行政区同时也是一个县）→ 区域

| 字段名 | 类型 | 含义 | 示例 |
| --- | --- | --- | --- |
| location_id | int | 区域编号 | 132 |
| zone_name | string | 区域名称 | JFK Airport |
| borough | string | 所属行政区 | Queens |
| service_zone | string | TLC 服务区分类 | Airports |
| is_airport | boolean | 是否机场（1 纽瓦克、132 JFK、138 拉瓜迪亚） | true |
| zone_category | string | 区域类别：普通 / 机场 / 纽约市外 / 未知 | 机场 |

## 3. 事实表

### 3.1 行程明细事实表 dwd_trip_detail

- **粒度：** 一行 = 一次完成的网约车行程
- **分区：** dt（上车日期），按天分区
- **数据来源：** ODS 原始行程表
- **处理原则：** 行程真实发生就保留；某个字段不可用时，用标记字段标明，不删除行程

#### 主键与去重

- **主键：** trip_id，由全部原始字段拼接后计算 SHA-256 哈希值生成
- **为什么用哈希而不是自增编号：** 哈希值只由数据内容决定，同一份数据重跑多次，ID 不变（幂等），便于重跑和补数据
- **去重规则：** 加工时先对所有字段完全相同的行去重
- **探查依据：** 2024 年 12 月数据中，完全重复的行为 0 条；按"平台、叫车时间、上车时间、下车时间、上下车区域"判断，仅 1 组 2 条记录重复（为拼车行程，两条记录的部分字段不同），对指标无影响

#### 主键与关联维度的字段

| 字段名 | 类型 | 含义 | 来源 / 计算规则 | 关联的维度表 |
| --- | --- | --- | --- | --- |
| trip_id | string | 行程 ID（主键） | sha2(concat_ws('\|', 全部原始字段), 256) | — |
| dt | date | 上车日期（同时是分区字段） | to_date(pickup_datetime) | dim_date.date |
| pickup_hour | int | 上车小时，0–23 | hour(pickup_datetime) | dim_time_slot.hour |
| pu_location_id | int | 上车区域 ID | PULocationID | dim_zone.location_id（上车） |
| do_location_id | int | 下车区域 ID | DOLocationID | dim_zone.location_id（下车） |
| platform_code | string | 平台牌照编号 | hvfhs_license_num | dim_platform.platform_code |

#### 时间点

| 字段名 | 类型 | 含义 | 来源 |
| --- | --- | --- | --- |
| request_datetime | timestamp | 叫车时间（Uber 预约订单为预约上车时间） | request_datetime |
| on_scene_datetime | timestamp | 司机到达时间（Lyft 几乎不上报，不参与指标计算） | on_scene_datetime |
| pickup_datetime | timestamp | 上车时间 | pickup_datetime |
| dropoff_datetime | timestamp | 下车时间 | dropoff_datetime |

**说明：** 时间均为纽约当地时间。Spark 会话时区设为 America/New_York。

#### 时长和里程

| 字段名 | 类型 | 含义 | 来源 / 计算规则 |
| --- | --- | --- | --- |
| wait_seconds | bigint | 乘客等待时长（秒） | timestampdiff(SECOND, request_datetime, pickup_datetime) |
| trip_seconds | bigint | 行程时长（秒） | trip_time |
| trip_miles | double | 行程里程（英里） | trip_miles |

#### 金额

| 字段名 | 类型 | 含义 | 钱归谁 | 来源 / 计算规则 |
| --- | --- | --- | --- | --- |
| base_passenger_fare | double | 基础车费 | 平台和司机分配 | base_passenger_fare |
| tolls | double | 过路费 | 代收代付 | tolls |
| bcf | double | 黑车基金 | 基金（为司机提供工伤保险） | bcf |
| sales_tax | double | 纽约州销售税 | 州政府 | sales_tax |
| congestion_surcharge | double | 拥堵附加费 | 州政府 | congestion_surcharge |
| airport_fee | double | 机场费 | 机场管理方 | airport_fee |
| cbd_congestion_fee | double | 中心商务区拥堵费 | 纽约大都会运输署 | COALESCE(cbd_congestion_fee, 0)（2025-01-05 起收取，此前为空，按 0 处理） |
| tips | double | 小费 | 全部归司机 | tips |
| passenger_total_fare | double | 乘客支付总额 | — | 以上八项之和 |
| driver_pay | double | 司机收入（不含过路费和小费，已扣除平台佣金） | 司机 | driver_pay |

**注意：** 在 SQL 中任何数与 NULL 相加结果都是 NULL，所以 cbd_congestion_fee 必须用 COALESCE 处理，否则 2024 年 12 月的乘客支付总额会全部变成空值。

#### 服务标记

| 字段名 | 类型 | 含义 | 来源 / 计算规则 |
| --- | --- | --- | --- |
| is_shared_request | boolean | 乘客是否请求拼车 | shared_request_flag = 'Y' |
| is_shared_match | boolean | 是否拼车成功 | shared_match_flag = 'Y' |
| is_wav_request | boolean | 是否请求无障碍车辆 | wav_request_flag = 'Y' |
| is_wav_match | boolean | 是否由无障碍车辆完成 | wav_match_flag = 'Y' |
| is_access_a_ride | boolean | 是否为 Access-A-Ride 行程 | access_a_ride_flag = 'Y' |

#### 数据有效性标记

| 字段名 | 类型 | 为真的条件 | 依据（探查发现） |
| --- | --- | --- | --- |
| is_wait_time_valid | boolean | pickup_datetime > request_datetime，且不满足"平台为 HV0003 并且叫车时间秒数为 0" | 上车早于或等于叫车约 25.1 万条；Uber 预约订单的叫车时间记录的是预约时间，秒数为 0 |
| is_fare_valid | boolean | base_passenger_fare > 0 且 driver_pay > 0 | 基础车费 ≤ 0 约 3.4 万条；司机收入 ≤ 0 约 6 千条 |
| is_trip_time_valid | boolean | trip_time > 0，且与"下车 − 上车"相差不超过 60 秒 | trip_time 与时间差不一致约 9,700 条 |

#### 已知局限

- **等待时长：** 用"秒数为 0"识别 Uber 预约订单，会误伤约 1.67% 的普通订单。下单时刻落在第几秒与等待时长无关，误伤是随机的，不会使平均值产生系统性偏差。Lyft 正常行程中秒数为 0 的比例为 1.66%，与随机水平一致，因此该规则只对 Uber 使用。
- **抽成率：** 司机收入大于基础车费时，抽成率为负，可能是平台补贴，视为有效数据。

## 4. 指标口径

（待编写）

### 4.1 已确定的口径要点

- **乘客等待时长：** 上车时间 − 叫车时间，只使用 is_wait_time_valid 为真的行程
- **行程时长：** 统一使用 trip_time，只使用 is_trip_time_valid 为真的行程
- **平台抽成率：** (基础车费 − 司机收入) ÷ 基础车费，只使用 is_fare_valid 为真的行程。不使用乘客支付总额计算，因为小费归司机，税费和附加费交给政府、基金和机场，都不是平台收入
- **机场订单：** 上车或下车任一端在机场（dim_zone.is_airport 为真），包括纽瓦克、JFK、拉瓜迪亚
- **不计算"接驾时长"（到达 − 叫车）：** Lyft 99.7% 的行程没有到达时间，无法跨平台比较

## 5. 设计依据：探查发现与设计决策的对应

| 设计 | 探查中的发现 |
| --- | --- |
| 按上车日期分区 | 文件严格按上车时间划分月份；叫车时间会跨月 |
| 等待时长 = 上车 − 叫车 | Lyft 99.7% 的行程没有到达时间 |
| is_wait_time_valid | Uber 预约订单的叫车时间是预约时间（秒数为 0 的比例 98%）；上车早于叫车约 25.1 万条 |
| 行程时长用 trip_time | trip_time 与"下车 − 上车"99.95% 一致 |
| is_fare_valid | 基础车费 ≤ 0 约 3.4 万条；司机收入 ≤ 0 约 6 千条，最长的 10 条行程中有 6 条司机收入为负 |
| 到达时间原样保留，不参与指标 | Lyft 几乎不上报到达时间 |
| 机场按上车或下车判断 | 纽瓦克机场全月仅 1 条上车记录 |
| 区域维度增加 is_airport | 上车最多的两个区域是拉瓜迪亚和 JFK 机场 |
| 特殊区域作为单独类别保留 | 约 4.4% 的行程在"纽约市外"或"未知"区域下车 |
| 极端值不删除 | 最长行程 555 英里，时速 37–68 英里，各字段相互吻合，是真实的长途行程 |
| 时段按数据划分 | 3 点最低，18–19 点最高，晚高峰持续到深夜 |
| 主键用全字段哈希 | 完全重复 0 条；身份字段相同仅 1 组 |
