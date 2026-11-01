-- 区域维度：来自 ODS 的 TLC 区域对照表，补充机场和特殊区域标记
CREATE TABLE IF NOT EXISTS tlc.dim_zone (
    location_id    INT      COMMENT '区域编号',
    zone_name      STRING   COMMENT '区域名称',
    borough        STRING   COMMENT '所属行政区',
    service_zone   STRING   COMMENT 'TLC 服务区分类',
    is_airport     BOOLEAN  COMMENT '是否机场（1 纽瓦克、132 JFK、138 拉瓜迪亚）',
    zone_category  STRING   COMMENT '区域类别：普通 / 机场 / 纽约市外 / 未知'
)
USING PARQUET
COMMENT 'DIM: 区域维度';

INSERT OVERWRITE TABLE tlc.dim_zone
SELECT
    LocationID                    AS location_id,
    Zone                          AS zone_name,
    Borough                       AS borough,
    service_zone,
    LocationID IN (1, 132, 138)   AS is_airport,
    CASE
        WHEN LocationID IN (1, 132, 138) THEN '机场'
        WHEN LocationID = 265            THEN '纽约市外'
        WHEN LocationID = 264            THEN '未知'
        ELSE '普通'
    END                           AS zone_category
FROM tlc.ods_taxi_zone;