# ProyectoRehabilitaciones_RSS

## Proyecto Final M4 - Gestion y Gobernanza de Datos con Unity Catalog

Pipeline de datos sobre sesiones de rehabilitacion del sistema de salud costarricense, implementado en Databricks con arquitectura Medallion (Bronze -> Silver -> Gold), gobernanza con Unity Catalog, pipeline declarativo SDP, modelo de machine learning y CI/CD con Declarative Automation Bundles (DAB, targets dev/prod).

---

## Informacion del Proyecto

| Campo | Valor |
|------|------|
| Universidad | Universidad Latina de Costa Rica |
| Carrera | Tecnico en Ingenieria de Datos con Databricks |
| Modulo | M4 - Gestion y Gobernanza de Datos con Unity Catalog |
| Estudiante | Jonathan Hernandez |
| Correo | jonathan.hernandez1@ulatina.net |
| Docente | Andres Calvo Vargas |
| Fecha | Octubre 2026 |

---

## Dataset

* **Archivo fuente:** `DS_REHABILITACION_RSS.csv`
* **Ubicacion:** volumen de Unity Catalog `/Volumes/workspace/default/rehabilitacion_rss`
* **Delimitador:** punto y coma (`;`), encoding ISO-8859-1
* **Dominio:** sesiones de rehabilitacion del sistema de salud costarricense
* **Volumen:** 115,799 filas | 7,077 pacientes | 138 terapeutas

### Jerarquia de los datos

```
CEDULA (paciente)
  L__ NUM_CASO (caso clinico; una cedula puede tener varios casos)
        L__ FECHA_SOLICITUD (ciclo de terapia; un caso puede tener varios ciclos)
              L__ NUMERO_SESION + FECHA_HORA_RH (sesiones dentro del ciclo)
```

### Llaves de negocio

* **Paciente:** `CEDULA`
* **Caso clinico:** `NUM_CASO`
* **Ciclo de terapia:** `NUM_CASO` + `FECHA_SOLICITUD`
* **Sesion (PK):** `NUM_CASO` + `FECHA_SOLICITUD` + `NUMERO_SESION`

### Diccionario de datos (resumen)

| Grupo | Columnas |
|-------|----------|
| Paciente | `CEDULA`, `NOMBRE_PACIENTE`, `GENERO`, `FECHA_NACIMIENTO` |
| Caso | `NUM_CASO`, `NUM_CASO_ADM`, `FECHA_ACCIDENTE`, `FECHA_CASO` |
| Terapia | `FECHA_SOLICITUD`, `COD_CLINICA`, `CLINICA_TERAPIA`, `TIPO_TERAPIA`, `CANT_SESIONES_PROG`, `CANT_SESIONES_EFEC` |
| Sesion | `NUMERO_SESION`, `FECHA_HORA_RH`, `COD_ESTADO_SESION`, `DESC_ESTADO_SESION` (REALIZADA / PROGRAMADA / ANULADA) |
| Ingreso/Egreso | `COD_INGRESO_RH`, `DESC_INGRESO_RH`, `COD_EGRESO_RH`, `DESC_EGRESO_RH` |
| Terapeuta | `COD_TERAPEUTA`, `TERAPEUTA` |

---

## Arquitectura Medallion

```mermaid
graph TB
    CSV[DS_REHABILITACION_RSS.csv<br/>Volumen UC workspace.default.rehabilitacion_rss]
    BRONZE[(rehabilitacion_bronze<br/>115,799 filas - COPY INTO incremental<br/>_source_file en cada fila)]
    SILVER[(rehabilitacion_silver<br/>110,804 filas - tipos correctos, nulos tratados<br/>deduplicacion, JOIN con dim_terapeuta)]
    GOLD[(hecho_sesiones_rehabilitacion<br/>Modelo estrella: tabla de hechos + 3 dimensiones)]

    CSV -->|COPY INTO (2 lotes)| BRONZE
    BRONZE -->|Limpieza y transformacion| SILVER
    SILVER -->|Modelo estrella (O6)| GOLD
```

---

## Componentes del proyecto

| # | Componente | Tipo | Estado |
|---|------------|------|--------|
| V1 | Bronze - Ingesta incremental (COPY INTO) | Columna vertebral | Completado |
| V2 | Silver - Limpieza y transformacion | Columna vertebral | Completado |
| O6 | Modelo estrella (gold: hechos + dimensiones) | Reemplaza C1 | Completado |
| O8 | Lakeflow Spark Declarative Pipelines | Reemplaza C2 | Completado |
| C3 | Gobernanza (esquemas, privilegios, row filter, tags) | Componente del examen | Completado |
| C4 | CI/CD (Git folder, PR a main, databricks.yml) | Componente del examen | Completado |
| C5 | Observabilidad y optimizacion (system tables + liquid clustering) | Componente del examen | Completado |
| O3 | Machine Learning (riesgo de abandono con MLflow) | Tema adicional | Completado |
| O9 | Agentes (documentacion del uso de Genie Code) | Tema adicional | Completado |
| DA | Dashboard AI/BI (13 widgets sobre el modelo estrella) | Entregable adicional | Completado |

---

## Resumen de implementacion

### V1 - Bronze: ingesta incremental

* Metodo: `COPY INTO` (idempotente por diseno) sobre la tabla Delta `workspace.default.rehabilitacion_bronze`
* Dos lotes: `lote_1.csv` (58,028 filas) + `lote_2.csv` (57,771 filas) = 115,799 filas totales
* Columna `_source_file` registra el archivo de origen de cada fila
* Evidencia: conteo por lote tras dos cargas; cada lote aparece una sola vez (sin duplicacion)

### V2 - Silver: limpieza y transformacion

* Tipos corregidos: fechas a DATE/TIMESTAMP, codigos a INT
* Nulos tratados con regla explicable: fechas no parseables -> NULL, strings descriptivos -> 'DESCONOCIDO'
* Deduplicacion por llave de negocio (`NUM_CASO` + `FECHA_SOLICITUD` + `NUMERO_SESION`): 4,995 duplicados eliminados, 110,804 filas finales
* JOIN con `dim_terapeuta` (138 terapeutas)
* Celdas de metricas ANTES y DESPUES de la transformacion

### O6 - Modelo estrella (reemplaza C1: Gold y calidad)

* Tabla de hechos `hecho_sesiones_rehabilitacion` (110,804 filas) con PRIMARY KEY informativa
* Tres dimensiones: `dim_paciente` (7,077), `dim_terapeuta` (138), `dim_estado_sesion` (3)
* FOREIGN KEYS declaradas de hechos a dimensiones
* Reglas de calidad: NOT NULL en llaves y expectations en el pipeline SDP (O8)
* Dos consultas analiticas de negocio ejecutadas sobre el modelo

### O8 - Pipeline declarativo SDP (reemplaza C2: Orquestacion)

* Pipeline `Pipeline_Rehabilitacion_M4` (compute serverless, Photon activado)
* Streaming tables: `sdp_bronze_rehabilitacion` (Auto Loader), `sdp_silver_rehabilitacion`
* Materialized views: `sdp_dim_terapeuta`, `sdp_dim_paciente`, `sdp_dim_estado_sesion`, `sdp_hecho_sesiones`
* Expectations de calidad en Silver (llaves NOT NULL, numero de sesion positiva, DROP ROW)
* Actualizacion COMPLETED con los 6 datasets creados

### C3 - Gobernanza

* Esquemas por capa: `bronze_rehab`, `silver_rehab`, `gold_rehab`
* Privilegios de minimo privilegio: GRANT SELECT a `account users`, verificado con SHOW GRANTS
* Row filter con tabla de mapeo: UDF `can_access_clinica` + tabla `user_clinica_map`
* Filtrado verificado: 21,232 filas visibles vs 110,804 totales
* Tags PII en columnas sensibles: `CEDULA`, `NOMBRE_PACIENTE`, `FECHA_NACIMIENTO` (pii_identificador, pii_nombre, dato_sensible)

### C4 - CI/CD (este repositorio)

* Git folder conectado a GitHub con Personal Access Token fine-grained
* Bundle DAB en `rehabilitacion/` con `databricks.yml` targets `dev` y `prod`
* Pipeline SDP declarado como recurso del bundle: `resources/pipeline_rehabilitacion_m4.pipeline.yml`
* Validacion: `bundle validate --target dev` OK, `--target prod` OK
* Flujo Git: rama `dev` -> commit -> push -> pull request integrado a `main`

### C5 - Observabilidad y optimizacion

* System tables: `system.access.audit` (50 eventos unityCatalog), `system.access.table_lineage` (37 registros de linaje bronze -> silver -> gold), `event_log()` del pipeline SDP (30 eventos)
* Liquid clustering en la tabla de hechos: `CLUSTER BY (COD_CLINICA, FECHA_SOLICITUD)`
* `OPTIMIZE` ejecutado; evidencia en `DESCRIBE DETAIL` (clusteringColumns) y `DESCRIBE HISTORY` (CREATE, WRITE, CLUSTER BY, OPTIMIZE)

### O3 - Machine Learning: riesgo de abandono

* Features por paciente desde Silver (11 variables: sesiones, cumplimiento, clinicas, dias desde ultima sesion, edad, genero)
* RandomForestClassifier (scikit-learn), train/test 80/20 estratificado
* Metricas: accuracy 98.45% | precision 90.13% | recall 95.14% | F1 92.57%
* Modelo guardado en experimento MLflow `/Shared/rehabilitacion_abandono_m4`
* Tabla `riesgo_abandono_paciente`: 7,077 pacientes (708 riesgo ALTO, 39 MEDIO, 6,330 BAJO)
* Variables mas importantes: `tasa_cumplimiento` (44.6%) y `total_anuladas` (37.3%)

### O9 - Agentes

* Documentacion del uso de Genie Code (agente IA dentro de Databricks) para implementar el proyecto
* Incluye que se le pidio, que implemento y 12 correcciones documentadas (esquemas de system tables, sintaxis SQL, columnas inexistentes, JOINs del modelo estrella, entre otras)

### Dashboard AI/BI

* 13 widgets sobre el modelo estrella: 4 KPIs (sesiones, pacientes, tasa de cumplimiento, riesgo), bar charts, pie, line, tabla y 3 filtros
* Datasets SQL con JOINs a las dimensiones (`dim_estado_sesion`, `dim_terapeuta`)

---

## Estructura del repositorio

```
ProyectoRehabilitaciones_RSS/
|-- README.md                  <- esta guia del proyecto
|-- rehabilitacion/            <- raiz del bundle (DAB)
    |-- databricks.yml         <- targets dev y prod
    |-- README.md              <- documentacion del bundle
    |-- resources/
    |   L__ pipeline_rehabilitacion_m4.pipeline.yml   <- pipeline SDP como recurso
    L__ src/
        L__ transformations/
            |-- 01_bronze.sql   <- streaming table (Auto Loader)
            |-- 02_silver.sql   <- limpieza, tipos, expectations
            L__ 03_gold.sql    <- modelo estrella (hechos + dimensiones)
```

El notebook guia completo con la implementacion y las evidencias ejecutadas (61 celdas) vive en el workspace de Databricks: `Guia_Proyecto_Final_M4_Rehabilitacion`.

---

## Despliegue

```bash
# Validar el bundle
databricks bundle validate --target dev
databricks bundle validate --target prod

# Desplegar (dev antepone [dev <usuario>] al nombre de los recursos)
databricks bundle deploy --target dev
databricks bundle deploy --target prod
```

Se requiere autenticacion con el workspace de Databricks (`databricks auth login` o variables `DATABRICKS_HOST` + token).
