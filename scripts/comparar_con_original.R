# Compara las tablas del libro compilado (docs/) con las del documento original
# (original/tablas/*.csv, recuperadas del HTML publicado antes de perder los .Rmd).
# Uso, desde la carpeta del proyecto: Rscript scripts/comparar_con_original.R
suppressPackageStartupMessages({ library(xml2); library(rvest) })

normalizar <- function(x) {
  x[] <- trimws(gsub("\\s+", " ", as.character(x)))  # conserva las dimensiones de una matriz
  x
}

resultado <- list()
for (html in list.files("docs", pattern = "\\.html$", full.names = TRUE)) {
  doc <- read_html(html, encoding = "UTF-8")
  for (tab in xml_find_all(doc, "//table[caption]")) {
    ids <- xml_attr(xml_find_all(tab, ".//caption//span[starts-with(@id,'tab:')]"), "id")
    if (!length(ids)) next
    label <- sub("^tab:", "", ids[1])
    original <- file.path("original", "tablas", paste0(label, ".csv"))
    if (!file.exists(original)) next
    xml_remove(xml_find_all(tab, ".//tfoot"))
    nueva <- html_table(tab, header = TRUE, convert = FALSE)
    vieja <- read.csv(original, check.names = FALSE, colClasses = "character", encoding = "UTF-8")
    iguales <- identical(dim(nueva), dim(vieja)) &&
      identical(normalizar(names(nueva)), normalizar(names(vieja))) &&
      all(mapply(function(a, b) identical(normalizar(a), normalizar(b)), nueva, vieja))
    diferencias <- if (iguales || !identical(dim(nueva), dim(vieja))) NA_integer_ else
      sum(normalizar(as.matrix(nueva)) != normalizar(as.matrix(vieja)))
    resultado[[label]] <- data.frame(tabla = label, filas = nrow(nueva), igual = iguales,
                                     celdas_distintas = diferencias,
                                     dim_original = paste(dim(vieja), collapse = "x"),
                                     dim_nueva = paste(dim(nueva), collapse = "x"))
    if (!iguales && identical(dim(nueva), dim(vieja))) {
      d <- which(normalizar(as.matrix(nueva)) != normalizar(as.matrix(vieja)), arr.ind = TRUE)
      for (i in seq_len(min(nrow(d), 6))) {
        cat(sprintf("  %s [fila %d, %s]: original '%s' | nuevo '%s'\n", label, d[i, 1], names(vieja)[d[i, 2]],
                    vieja[d[i, 1], d[i, 2]], nueva[[d[i, 2]]][d[i, 1]]))
      }
    }
  }
}
print(do.call(rbind, resultado), row.names = FALSE)
