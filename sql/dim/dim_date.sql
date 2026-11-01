-- 日期维度：用 SQL 生成 2024-01-01 至 2026-12-31 的每一天；节假日为人工维护的美国联邦假日
CREATE TABLE IF NOT EXISTS tlc.dim_date (
    date          DATE     COMMENT '日期，与事实表的 dt 对应',
    date_key      INT      COMMENT '整型日期，如 20241225',
    year          INT      COMMENT '年',
    quarter       INT      COMMENT '季度',
    month         INT      COMMENT '月',
    week_of_year  INT      COMMENT '一年中的第几周（ISO 标准）',
    day_of_week   INT      COMMENT '星期几，1 = 周一，7 = 周日',
    day_name      STRING   COMMENT '星期名称',
    is_weekend    BOOLEAN  COMMENT '是否周末',
    is_holiday    BOOLEAN  COMMENT '是否美国联邦假日',
    holiday_name  STRING   COMMENT '节假日名称',
    is_workday    BOOLEAN  COMMENT '是否工作日（非周末且非节假日）'
)
USING PARQUET
COMMENT 'DIM: 日期维度';

WITH dates AS (
    SELECT explode(sequence(DATE '2024-01-01', DATE '2026-12-31', INTERVAL 1 DAY)) AS d
),
holidays AS (
    SELECT * FROM VALUES
        (DATE '2024-01-01', 'New Year''s Day'),
        (DATE '2024-01-15', 'Martin Luther King Jr. Day'),
        (DATE '2024-02-19', 'Presidents'' Day'),
        (DATE '2024-05-27', 'Memorial Day'),
        (DATE '2024-06-19', 'Juneteenth'),
        (DATE '2024-07-04', 'Independence Day'),
        (DATE '2024-09-02', 'Labor Day'),
        (DATE '2024-10-14', 'Columbus Day'),
        (DATE '2024-11-11', 'Veterans Day'),
        (DATE '2024-11-28', 'Thanksgiving Day'),
        (DATE '2024-12-25', 'Christmas Day'),
        (DATE '2025-01-01', 'New Year''s Day'),
        (DATE '2025-01-20', 'Martin Luther King Jr. Day'),
        (DATE '2025-02-17', 'Presidents'' Day'),
        (DATE '2025-05-26', 'Memorial Day'),
        (DATE '2025-06-19', 'Juneteenth'),
        (DATE '2025-07-04', 'Independence Day'),
        (DATE '2025-09-01', 'Labor Day'),
        (DATE '2025-10-13', 'Columbus Day'),
        (DATE '2025-11-11', 'Veterans Day'),
        (DATE '2025-11-27', 'Thanksgiving Day'),
        (DATE '2025-12-25', 'Christmas Day'),
        (DATE '2026-01-01', 'New Year''s Day'),
        (DATE '2026-01-19', 'Martin Luther King Jr. Day'),
        (DATE '2026-02-16', 'Presidents'' Day'),
        (DATE '2026-05-25', 'Memorial Day'),
        (DATE '2026-06-19', 'Juneteenth'),
        (DATE '2026-07-04', 'Independence Day'),
        (DATE '2026-09-07', 'Labor Day'),
        (DATE '2026-10-12', 'Columbus Day'),
        (DATE '2026-11-11', 'Veterans Day'),
        (DATE '2026-11-26', 'Thanksgiving Day'),
        (DATE '2026-12-25', 'Christmas Day')
    AS h(holiday_date, holiday_name)
)
INSERT OVERWRITE TABLE tlc.dim_date
SELECT
    d                                         AS date,
    CAST(date_format(d, 'yyyyMMdd') AS INT)   AS date_key,
    year(d)                                   AS year,
    quarter(d)                                AS quarter,
    month(d)                                  AS month,
    weekofyear(d)                             AS week_of_year,
    weekday(d) + 1                            AS day_of_week,
    CASE weekday(d)
        WHEN 0 THEN '周一' WHEN 1 THEN '周二' WHEN 2 THEN '周三'
        WHEN 3 THEN '周四' WHEN 4 THEN '周五' WHEN 5 THEN '周六'
        ELSE '周日'
    END                                       AS day_name,
    weekday(d) >= 5                           AS is_weekend,
    h.holiday_date IS NOT NULL                AS is_holiday,
    h.holiday_name                            AS holiday_name,
    weekday(d) < 5 AND h.holiday_date IS NULL AS is_workday
FROM dates
LEFT JOIN holidays h ON dates.d = h.holiday_date;