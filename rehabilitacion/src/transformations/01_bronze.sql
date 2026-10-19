-- ============================================================
-- CAPA BRONZE - Streaming Table con Auto Loader
-- ============================================================
-- Ingesta incremental de archivos CSV desde el volumen de lotes.
-- Todas las columnas se leen como STRING (datos crudos).
-- El pipeline gestiona automaticamente schemaLocation y checkpoint
-- (no se pasan como opciones en SDP).
-- _source_file registra el archivo de origen de cada fila.
--  Test


CREATE OR REFRESH STREAMING TABLE sdp_bronze_rehabilitacion
COMMENT 'Capa Bronze: datos crudos de rehabilitacion RSS ingestados con Auto Loader'
AS SELECT
  *,
  _metadata.file_path AS _source_file
FROM STREAM(read_files(
  '/Volumes/workspace/default/rehabilitacion_rss/lotes/',
  format => 'csv',
  header => true,
  sep => ';',
  encoding => 'ISO-8859-1',
  inferColumnTypes => false
));
