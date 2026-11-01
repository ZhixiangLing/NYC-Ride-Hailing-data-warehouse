-- 平台维度：人工维护的码表，依据 TLC 数据字典
CREATE TABLE IF NOT EXISTS tlc.dim_platform (
    platform_code  STRING   COMMENT '平台牌照编号，如 HV0003',
    platform_name  STRING   COMMENT '平台名称',
    is_active      BOOLEAN  COMMENT '是否仍在运营'
)
USING PARQUET
COMMENT 'DIM: 平台维度';

INSERT OVERWRITE TABLE tlc.dim_platform VALUES
    ('HV0002', 'Juno', false),
    ('HV0003', 'Uber', true),
    ('HV0004', 'Via',  false),
    ('HV0005', 'Lyft', true);
    