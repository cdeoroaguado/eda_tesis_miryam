# Análisis de datos de sensibilidad intercultural (tesis de Miryam)

Bookdown con el análisis de datos de la tesis. Se publica en GitHub Pages desde la carpeta `docs/`.
Todas las tablas y figuras se calculan a partir de la base de datos, excepto el mapa.

## Estructura

| Archivo / carpeta | Contenido |
|---|---|
| `index.Rmd` | Encabezado YAML, carga y preparación de datos, Capítulo 1: Contexto del problema |
| `01-operacionalizacion.Rmd` | Capítulo 2: Operacionalización de las variables |
| `02-eda.Rmd` | Capítulo 3: Análisis exploratorio |
| `03-validacion.Rmd` | Capítulo 4: Validación del instrumento y perfiles (clúster jerárquico, PERMANOVA) |
| `04-cuanti.Rmd` | Capítulo 5: Análisis cuantitativo pretest/postest |
| `05-referencias.Rmd` | Referencias |
| `datos/` | Base de datos `ESCALA DE SENSIBILIDAD DATA 1 Y DATA 2.xlsx` (**no se sube a GitHub**: tiene nombres de estudiantes) |
| `tablas/` | Tablas de operacionalización (definiciones, no resultados) |
| `img/mapa-1.png` | Mapa de estudiantes por municipio (imagen original, ver abajo) |
| `original/` | Tablas y figuras del documento original, usadas como referencia de verificación |
| `scripts/comparar_con_original.R` | Compara las tablas del libro compilado con las del documento original |
| `docs/` | Libro compilado (HTML) |

## Compilar

Desde R (o RStudio, botón *Build Book*), en la carpeta del proyecto:

```r
bookdown::render_book("index.Rmd")
```

Paquetes requeridos: `bookdown`, `readxl`, `dplyr`, `tidyr`, `ggplot2`, `kableExtra`, `psych`,
`cluster`, `factoextra`, `vegan`.

Para comprobar que los resultados siguen coincidiendo con el documento original:

```r
source("scripts/comparar_con_original.R")
```

## Decisiones del análisis

- **Datos.** Hoja `data` = pretest (n = 48, con sociodemográficas); hoja `data 2` = postest (n = 43 que
  respondieron). Las filas de ambas hojas corresponden al mismo estudiante.
- **Ítems invertidos** (Ruiz Bernardo, 2012): P2, P4, P10, P13, P15, P18, P20 y P22.
- **Alfa de Respeto (D2).** Por decisión de la investigadora, en la tabla de fiabilidad por dimensión la
  polaridad de D2 se ajusta invirtiendo P2, P4, P8, P10, P20 y P22. El resto del análisis usa la
  recodificación general.
- **ISS Global** = media de los 21 ítems de D1–D4 (Disfrute, D5, se excluye por su baja consistencia).
- **Clúster.** Dimensiones D1–D4 escaladas por rango (0–1), distancia euclídea, Ward.D2, k = 2.

## Mapa

La figura del mapa es la imagen original: la cartografía municipal con la que se hizo (que incluye
Tuchín) no está en el proyecto. GADM y geoBoundaries no traen Tuchín como municipio. Para regenerarlo
haría falta el Marco Geoestadístico Nacional (MGN) del DANE.

## Historia (octubre 2026)

Los `.Rmd` originales se perdieron con un disco dañado; el repositorio solo tenía el libro compilado.
El proyecto se reconstruyó desde ese HTML (`scripts/convertir_html_a_rmd.R`) y, al recuperar la base
de datos, se reescribió para calcular todo desde los datos. 16 de las 17 tablas coinciden celda por
celda con el documento original; en la restante, dos valores difieren en el sexto decimal (redondeo).
