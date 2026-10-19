-- ============================================================
-- CAPA GOLD - Modelo Estrella (Materialized Views)
-- ============================================================
-- Grano de la tabla de hechos: una fila por sesion de rehabilitacion.
-- Dimensiones: sdp_dim_paciente, sdp_dim_estado_sesion
--              (sdp_dim_terapeuta ya creada en Silver)
-- La deduplicacion por llave de negocio se realiza aqui con ROW_NUMBER
-- (batch read) porque las streaming tables no soportan ROW_NUMBER.

-- ============================================================
-- GOLD - Dimension dim_paciente (Materialized View)
-- ============================================================

CREATE OR REFRESH MATERIALIZED VIEW sdp_dim_paciente (
  CEDULA STRING NOT NULL COMMENT 'Identificacion del paciente (PK)',
  NOMBRE_PACIENTE STRING COMMENT 'Nombre completo del paciente',
  GENERO STRING COMMENT 'Genero (HOMBRE / MUJER)',
  FECHA_NACIMIENTO DATE COMMENT 'Fecha de nacimiento',
  CONSTRAINT pk_sdp_paciente PRIMARY KEY (CEDULA)
)
COMMENT 'Dimension de pacientes con datos demograficos'
AS
SELECT DISTINCT
  CEDULA,
  NOMBRE_PACIENTE,
  GENERO,
  FECHA_NACIMIENTO
FROM sdp_silver_rehabilitacion
WHERE CEDULA IS NOT NULL;

-- ============================================================
-- GOLD - Dimension dim_estado_sesion (Materialized View)
-- ============================================================

CREATE OR REFRESH MATERIALIZED VIEW sdp_dim_estado_sesion (
  COD_ESTADO_SESION INT NOT NULL COMMENT 'Codigo del estado de sesion (PK)',
  DESC_ESTADO_SESION STRING COMMENT 'Descripcion del estado (REALIZADA, PROGRAMADA, etc.)',
  CONSTRAINT pk_sdp_estado_sesion PRIMARY KEY (COD_ESTADO_SESION)
)
COMMENT 'Dimension de estados de sesion de rehabilitacion'
AS
SELECT DISTINCT
  COD_ESTADO_SESION,
  DESC_ESTADO_SESION
FROM sdp_silver_rehabilitacion
WHERE COD_ESTADO_SESION IS NOT NULL;

-- ============================================================
-- GOLD - Tabla de hechos hecho_sesiones (Materialized View)
-- ============================================================
-- Deduplicacion por llave de negocio: NUM_CASO + FECHA_SOLICITUD +
-- NUMERO_SESION. Se mantiene la fila con id_fila mas alto.
-- PK y FK son informativas en Databricks (no enforced).

CREATE OR REFRESH MATERIALIZED VIEW sdp_hecho_sesiones (
  NUM_CASO STRING NOT NULL,
  FECHA_SOLICITUD TIMESTAMP NOT NULL,
  NUMERO_SESION INT NOT NULL,
  CEDULA STRING COMMENT 'FK -> sdp_dim_paciente.CEDULA',
  COD_TERAPEUTA INT COMMENT 'FK -> sdp_dim_terapeuta.cod_terapeuta',
  COD_ESTADO_SESION INT COMMENT 'FK -> sdp_dim_estado_sesion.COD_ESTADO_SESION',
  COD_CLINICA INT,
  CLINICA_TERAPIA STRING,
  TIPO_TERAPIA STRING,
  CANT_SESIONES_PROG INT COMMENT 'Sesiones programadas en el ciclo',
  CANT_SESIONES_EFEC INT COMMENT 'Sesiones efectivas en el ciclo',
  FECHA_HORA_RH TIMESTAMP COMMENT 'Fecha y hora de la sesion',
  _source_file STRING,
  CONSTRAINT pk_sdp_hecho PRIMARY KEY (NUM_CASO, FECHA_SOLICITUD, NUMERO_SESION),
  CONSTRAINT fk_sdp_paciente FOREIGN KEY (CEDULA) REFERENCES workspace.default.sdp_dim_paciente (CEDULA),
  CONSTRAINT fk_sdp_terapeuta FOREIGN KEY (COD_TERAPEUTA) REFERENCES workspace.default.sdp_dim_terapeuta (cod_terapeuta),
  CONSTRAINT fk_sdp_estado FOREIGN KEY (COD_ESTADO_SESION) REFERENCES workspace.default.sdp_dim_estado_sesion (COD_ESTADO_SESION)
)
COMMENT 'Tabla de hechos: una fila por sesion de rehabilitacion (deduplicada)'
AS
WITH dedup AS (
  SELECT *,
    ROW_NUMBER() OVER (
      PARTITION BY NUM_CASO, FECHA_SOLICITUD, NUMERO_SESION
      ORDER BY id_fila DESC
    ) AS rn
  FROM sdp_silver_rehabilitacion
)
SELECT
  NUM_CASO,
  FECHA_SOLICITUD,
  NUMERO_SESION,
  CEDULA,
  COD_TERAPEUTA,
  COD_ESTADO_SESION,
  COD_CLINICA,
  CLINICA_TERAPIA,
  TIPO_TERAPIA,
  CANT_SESIONES_PROG,
  CANT_SESIONES_EFEC,
  FECHA_HORA_RH,
  _source_file
FROM dedup
WHERE rn = 1
  AND NUM_CASO IS NOT NULL
  AND FECHA_SOLICITUD IS NOT NULL
  AND NUMERO_SESION IS NOT NULL;
