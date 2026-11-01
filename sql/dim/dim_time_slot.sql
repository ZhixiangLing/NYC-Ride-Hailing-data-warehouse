-- 时段维度：一天 24 个小时，每小时一行。时段划分依据探查阶段的 24 小时行程分布
CREATE TABLE IF NOT EXISTS tlc.dim_time_slot (
    hour       INT      COMMENT '小时，0-23',
    slot_name  STRING   COMMENT '时段名称',
    is_peak    BOOLEAN  COMMENT '是否高峰'
)
USING PARQUET
COMMENT 'DIM: 时段维度';

INSERT OVERWRITE TABLE tlc.dim_time_slot
SELECT
    hour,
    CASE
        WHEN hour BETWEEN 0  AND 5  THEN '深夜'
        WHEN hour = 6               THEN '早晨'
        WHEN hour BETWEEN 7  AND 9  THEN '早高峰'
        WHEN hour BETWEEN 10 AND 16 THEN '白天'
        WHEN hour BETWEEN 17 AND 20 THEN '晚高峰'
        ELSE '夜间'
    END AS slot_name,
    (hour BETWEEN 7 AND 9) OR (hour BETWEEN 17 AND 20) AS is_peak
FROM (SELECT explode(sequence(0, 23)) AS hour) t;