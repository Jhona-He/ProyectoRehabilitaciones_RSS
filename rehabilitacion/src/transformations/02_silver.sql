-- ============================================================
-- CAPA SILVER - Dimension de Terapeuta (Materialized View)
-- ============================================================
-- Terapeutas unicos extraidos de Bronze con ROW_NUMBER.
-- Se usa para estandarizar nombres en el JOIN de Silver.
-- PK: cod_terapeuta (NOT NULL, necesaria para FK en Gold).

CREATE OR REFRESH MATERIALIZED VIEW sdp_dim_terapeuta (
  cod_terapeuta INT NOT NULL COMMENT 'Codigo del terapeuta (PK)',
  nombre_terapeuta STRING COMMENT 'Nombre del terapeuta estandarizado',
  CONSTRAINT pk_sdp_terapeuta PRIMARY KEY (cod_terapeuta)
)
COMMENT 'Dimension de terapeutas con nombres estandarizados'
AS
SELECT cod_terapeuta, nombre_terapeuta
FROM (
  SELECT
    try_cast(COD_TERAPEUTA AS INT) AS cod_terapeuta,
    COALESCE(NULLIF(TERAPEUTA, ''), 'DESCONOCIDO') AS nombre_terapeuta,
    ROW_NUMBER() OVER (
      PARTITION BY try_cast(COD_TERAPEUTA AS INT)
      ORDER BY TERAPEUTA
    ) AS rn
  FROM sdp_bronze_rehabilitacion
  WHERE COD_TERAPEUTA IS NOT NULL
    AND TERAPEUTA IS NOT NULL
) WHERE rn = 1;

-- ============================================================
-- CAPA SILVER - Streaming Table con transformaciones
-- ============================================================
-- Lee desde Bronze con STREAM (procesamiento incremental).
-- Transformaciones aplicadas:
--   1. Correccion de tipos (fechas a DATE/TIMESTAMP, codigos a INT)
--   2. Tratamiento de nulos:
--      - Fechas: try_to_date/try_to_timestamp -> NULL si no parsean
--      - Strings descriptivos: COALESCE(NULLIF(..., ''), 'DESCONOCIDO')
--      - Codigos: try_cast -> NULL si no casteable
--   3. JOIN stream-static con sdp_dim_terapeuta para estandarizar nombres
--   4. Expectations de calidad de datos
--
-- Nota: La deduplicacion por llave de negocio (NUM_CASO + FECHA_SOLICITUD
-- + NUMERO_SESION) se realiza en la capa Gold (materialized view con
-- batch read) porque ROW_NUMBER no es compatible con streaming.

CREATE OR REFRESH STREAMING TABLE sdp_silver_rehabilitacion (
  CONSTRAINT num_caso_not_null EXPECT (NUM_CASO IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT cedula_not_null EXPECT (CEDULA IS NOT NULL),
  CONSTRAINT num_sesion_positivo EXPECT (NUMERO_SESION > 0)
)
COMMENT 'Capa Silver: datos limpios y tipados de rehabilitacion con expectations'
AS SELECT
  try_cast(id_fila AS INT) AS id_fila,
  CEDULA,
  COALESCE(NULLIF(NOMBRE_PACIENTE, ''), 'DESCONOCIDO') AS NOMBRE_PACIENTE,
  COALESCE(NULLIF(GENERO, ''), 'DESCONOCIDO') AS GENERO,
  try_to_date(FECHA_NACIMIENTO, 'd/M/yyyy') AS FECHA_NACIMIENTO,
  NUM_CASO,
  NUM_CASO_ADM,
  try_to_timestamp(FECHA_ACCIDENTE, 'd/M/yyyy HH:mm:ss') AS FECHA_ACCIDENTE,
  try_to_timestamp(FECHA_CASO, 'd/M/yyyy HH:mm:ss') AS FECHA_CASO,
  try_to_timestamp(FECHA_SOLICITUD, 'd/M/yyyy HH:mm:ss') AS FECHA_SOLICITUD,
  try_cast(COD_CLINICA AS INT) AS COD_CLINICA,
  COALESCE(NULLIF(CLINICA_TERAPIA, ''), 'DESCONOCIDO') AS CLINICA_TERAPIA,
  COALESCE(NULLIF(TIPO_TERAPIA, ''), 'DESCONOCIDO') AS TIPO_TERAPIA,
  try_cast(CANT_SESIONES_PROG AS INT) AS CANT_SESIONES_PROG,
  try_cast(CANT_SESIONES_EFEC AS INT) AS CANT_SESIONES_EFEC,
  try_cast(NUMERO_SESION AS INT) AS NUMERO_SESION,
  try_to_timestamp(FECHA_HORA_RH, 'd/M/yyyy HH:mm:ss') AS FECHA_HORA_RH,
  try_cast(COD_ESTADO_SESION AS INT) AS COD_ESTADO_SESION,
  COALESCE(NULLIF(DESC_ESTADO_SESION, ''), 'DESCONOCIDO') AS DESC_ESTADO_SESION,
  try_cast(COD_INGRESO_RH AS INT) AS COD_INGRESO_RH,
  COALESCE(NULLIF(DESC_INGRESO_RH, ''), 'DESCONOCIDO') AS DESC_INGRESO_RH,
  try_cast(COD_EGRESO_RH AS INT) AS COD_EGRESO_RH,
  COALESCE(NULLIF(DESC_EGRESO_RH, ''), 'DESCONOCIDO') AS DESC_EGRESO_RH,
  try_cast(b.COD_TERAPEUTA AS INT) AS COD_TERAPEUTA,
  dt.nombre_terapeuta AS TERAPEUTA,
  _source_file
FROM STREAM(sdp_bronze_rehabilitacion) b
LEFT JOIN sdp_dim_terapeuta dt
  ON try_cast(b.COD_TERAPEUTA AS INT) = dt.cod_terapeuta;
