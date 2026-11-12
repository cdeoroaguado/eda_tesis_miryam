# Reconstruye los .Rmd del bookdown a partir del HTML renderizado.
# Uso: Rscript convertir.R <dir_html_original> <dir_proyecto> <pandoc.exe>
suppressPackageStartupMessages({
  library(xml2)
  library(rvest)
})

args <- commandArgs(trailingOnly = TRUE)
src <- normalizePath(args[1], winslash = "/")
dst <- normalizePath(args[2], winslash = "/")
pandoc <- args[3]

dir.create(file.path(dst, "tablas"), showWarnings = FALSE)
dir.create(file.path(dst, "img"), showWarnings = FALSE)

capitulos <- c(
  "index.html"              = "index.Rmd",
  "operacionalizacion.html" = "01-operacionalizacion.Rmd",
  "eda.html"                = "02-eda.Rmd",
  "validacion.html"         = "03-validacion.Rmd",
  "cuanti.html"             = "04-cuanti.Rmd"
)

q <- function(x) paste0('"', gsub('"', '\\\\"', x), '"')
txt <- function(n) trimws(gsub("\\s+", " ", xml_text(n)))

# Reemplaza un nodo por un párrafo con un marcador de texto
marcar <- function(node, marca) {
  p <- read_xml(paste0("<p>", marca, "</p>"))
  xml_replace(node, p)
}

contador <- 0
nuevo_id <- function(prefijo) {
  contador <<- contador + 1
  sprintf("XX%s%03dXX", prefijo, contador)
}

# Alineación de columnas a partir del encabezado de la tabla
alineacion <- function(tab) {
  ths <- xml_find_all(tab, ".//thead//th")
  if (length(ths) == 0) ths <- xml_find_all(tab, ".//tr[1]/*")
  vapply(ths, function(th) {
    a <- xml_attr(th, "align")
    if (is.na(a)) {
      st <- xml_attr(th, "style")
      a <- if (is.na(st)) "left" else sub(".*text-align:\\s*([a-z]+).*", "\\1", st)
    }
    substr(a, 1, 1)
  }, character(1))
}

chunk_tabla <- function(tab, cap_label, n_tabla) {
  label <- cap_label$label
  if (is.na(label)) label <- sprintf("tabla-%s-%02d", cap_label$cap_prefix, n_tabla)
  # la nota al pie (tfoot) se separa antes de leer la tabla
  tfoot <- xml_find_first(tab, ".//tfoot")
  nota <- NA
  if (!inherits(tfoot, "xml_missing")) {
    nota <- trimws(sub("^Nota\\.\\s*", "", txt(tfoot)))
    xml_remove(tfoot)
  }
  df <- html_table(tab, header = TRUE, trim = TRUE, convert = FALSE)
  csv <- file.path("tablas", paste0(label, ".csv"))
  write.csv(df, file.path(dst, csv), row.names = FALSE, fileEncoding = "UTF-8", na = "")
  al <- paste(alineacion(tab), collapse = "")

  clase <- xml_attr(tab, "class")
  estilo <- xml_attr(tab, "style")
  kx <- !is.na(clase) && grepl("table", clase)
  opciones <- character(0)
  if (kx) {
    clases <- setdiff(strsplit(clase, " ")[[1]], "table")
    clases <- sub("^table-", "", clases)
    if (length(clases)) opciones <- c(opciones, sprintf("bootstrap_options = c(%s)", paste(q(clases), collapse = ", ")))
    opciones <- c(opciones, "full_width = FALSE")
    fs <- regmatches(estilo, regexpr("font-size: [0-9]+px", estilo))
    if (length(fs)) opciones <- c(opciones, sprintf("font_size = %s", gsub("\\D+", "", fs)))
  }
  # columnas combinadas (rowspan) -> collapse_rows
  col_rs <- integer(0)
  for (tr in xml_find_all(tab, ".//tbody/tr")) {
    tds <- xml_find_all(tr, "./td")
    if (length(tds) == ncol(df)) {
      col_rs <- which(!is.na(xml_attr(tds, "rowspan")))
      if (length(col_rs)) break
    }
  }

  cap <- cap_label$caption
  lineas <- c(
    sprintf("```{r %s, echo=FALSE}", label),
    sprintf("tab <- read.csv(%s, check.names = FALSE, colClasses = \"character\", encoding = \"UTF-8\")", q(csv)),
    sprintf("knitr::kable(tab, %salign = %s%s)%s",
            if (!is.na(cap)) paste0("caption = ", q(cap), ", ") else "",
            q(al),
            if (kx) ", format = \"html\"" else "",
            if (kx) " |>" else "")
  )
  if (kx) {
    extra <- sprintf("  kableExtra::kable_styling(%s)", paste(opciones, collapse = ", "))
    if (length(col_rs)) extra <- c(extra, sprintf("  kableExtra::collapse_rows(columns = %s, valign = \"middle\")",
                                                  if (length(col_rs) > 1) sprintf("%d:%d", min(col_rs), max(col_rs)) else col_rs))
    if (!is.na(nota)) extra <- c(extra, sprintf("  kableExtra::footnote(general = %s, general_title = \"Nota.\", footnote_as_chunk = TRUE)", q(nota)))
    if (length(extra) > 1) extra[-length(extra)] <- paste(extra[-length(extra)], "|>")
    lineas <- c(lineas, extra)
  }
  c(lineas, "```")
}

for (html in names(capitulos)) {
  contador <- 0
  doc <- read_html(file.path(src, html), encoding = "UTF-8")
  sec <- xml_find_first(doc, "//section[contains(@class,'normal')]")
  pref <- sub("\\.html$", "", html)
  bloques <- list()

  # Eliminar encabezado de título (va en el YAML), referencias por capítulo y anclas
  xml_remove(xml_find_all(sec, ".//div[@id='header']"))
  xml_remove(xml_find_all(sec, ".//div[@id='refs']"))
  for (h in xml_find_all(sec, ".//h3[a[@href='referencias.html#referencias']]")) xml_remove(h)
  xml_remove(xml_find_all(sec, ".//a[contains(@class,'anchor-section')]"))
  xml_remove(xml_find_all(sec, ".//span[contains(@class,'header-section-number')]"))

  # Citas: "Autor (<a href='#ref-key'>año</a>)" -> @key
  for (cit in xml_find_all(sec, ".//span[@class='citation']")) {
    keys <- sub("^#ref-", "", xml_attr(xml_find_all(cit, ".//a"), "href"))
    marca <- paste0("XXCITE", keys, "XX", collapse = "; ")
    xml_replace(cit, read_xml(paste0("<span>", marca, "</span>")))
  }

  # Matemáticas: <span class="math inline">\(...\)</span> -> $...$
  for (m in xml_find_all(sec, ".//span[contains(@class,'math')]")) {
    tex <- xml_text(m)
    display <- grepl("display", xml_attr(m, "class"))
    tex <- gsub("^\\s*\\\\[(\\[]|\\\\[)\\]]\\s*$", "", tex, perl = TRUE)
    id <- nuevo_id("MATH")
    bloques[[id]] <- if (display) paste0("$$", tex, "$$") else paste0("$", trimws(tex), "$")
    xml_replace(m, read_xml(paste0("<span>", id, "</span>")))
  }

  # Tablas
  n_tabla <- 0
  for (tab in xml_find_all(sec, ".//table")) {
    n_tabla <- n_tabla + 1
    capn <- xml_find_first(tab, "./caption")
    label <- NA; caption <- NA
    if (!inherits(capn, "xml_missing")) {
      ids <- xml_attr(xml_find_all(capn, ".//span[starts-with(@id,'tab:')]"), "id")
      if (length(ids)) label <- sub("^tab:", "", ids[1])
      xml_remove(xml_find_all(capn, ".//span[starts-with(@id,'tab:')]"))
      caption <- txt(capn)
      if (caption == "") caption <- NA
    }
    id <- nuevo_id("TAB")
    bloques[[id]] <- chunk_tabla(tab, list(label = label, caption = caption, cap_prefix = pref), n_tabla)
    marcar(tab, id)
  }

  # Figuras con leyenda (div.figure)
  for (fig in xml_find_all(sec, ".//div[contains(@class,'figure')]")) {
    img <- xml_find_first(fig, ".//img")
    label <- sub("^fig:", "", xml_attr(xml_find_first(fig, ".//span[starts-with(@id,'fig:')]"), "id"))
    cap <- xml_attr(img, "alt")
    archivo <- basename(xml_attr(img, "src"))
    file.copy(file.path(src, xml_attr(img, "src")), file.path(dst, "img", archivo), overwrite = TRUE)
    id <- nuevo_id("FIG")
    bloques[[id]] <- c(sprintf("```{r %s, echo=FALSE, fig.cap=%s, out.width=\"%spx\"}", label, q(cap), xml_attr(img, "width")),
                       sprintf("knitr::include_graphics(\"img/%s\")", archivo), "```")
    marcar(fig, id)
  }
  # Figuras sin leyenda: <p><img></p>
  etiquetas_tablas <- unlist(lapply(bloques, function(b) sub("^```\\{r ([^,]+),.*", "\\1", b[1])))
  for (img in xml_find_all(sec, ".//p/img")) {
    archivo <- basename(xml_attr(img, "src"))
    label <- sub("-[0-9]+\\.png$", "", archivo)
    if (label %in% etiquetas_tablas) label <- paste0(label, "-graf")
    file.copy(file.path(src, xml_attr(img, "src")), file.path(dst, "img", archivo), overwrite = TRUE)
    id <- nuevo_id("FIG")
    bloques[[id]] <- c(sprintf("```{r %s, echo=FALSE, out.width=\"%spx\"}", label, xml_attr(img, "width")),
                       sprintf("knitr::include_graphics(\"img/%s\")", archivo), "```")
    marcar(xml_parent(img), id)
  }

  # Código R visible (no se puede evaluar: no hay datos)
  for (cb in xml_find_all(sec, ".//div[@class='sourceCode']")) {
    codigo <- xml_text(xml_find_first(cb, ".//code"))
    id <- nuevo_id("CODE")
    bloques[[id]] <- c("```{r, echo=TRUE, eval=FALSE}", strsplit(codigo, "\n")[[1]], "```")
    marcar(cb, id)
  }
  # Salidas de consola (pre sin clase) -> bloque de texto literal
  for (pre in xml_find_all(sec, ".//pre[not(@class)]")) {
    salida <- xml_text(pre)
    id <- nuevo_id("OUT")
    bloques[[id]] <- c("```", sub("\n$", "", strsplit(salida, "\n")[[1]]), "```")
    marcar(pre, id)
  }

  # Secciones: el id del div pasa al encabezado y se desenvuelve el div
  divs <- xml_find_all(sec, ".//div[contains(concat(' ',@class,' '),' section ')]")
  for (d in rev(divs)) {
    h <- xml_find_first(d, "./*[self::h1 or self::h2 or self::h3 or self::h4]")
    xml_attr(h, "id") <- xml_attr(d, "id")
    if (grepl("unnumbered", xml_attr(d, "class"))) xml_attr(h, "class") <- "unnumbered"
    for (ch in xml_contents(d)) xml_add_sibling(d, ch, .where = "before")
    xml_remove(d)
  }

  tmp <- tempfile(fileext = ".html")
  writeLines(c("<html><body>", as.character(xml_contents(sec)), "</body></html>"), tmp, useBytes = TRUE)
  md <- system2(pandoc, c("-f", "html", "-t", "markdown-raw_html-native_divs-native_spans-fenced_divs-bracketed_spans-link_attributes",
                          "--wrap=none", shQuote(tmp)), stdout = TRUE)
  Encoding(md) <- "UTF-8"
  md <- paste(md, collapse = "\n")

  for (id in names(bloques)) md <- sub(id, paste(bloques[[id]], collapse = "\n"), md, fixed = TRUE)
  md <- gsub("XXCITE([A-Za-z0-9_-]+)XX", "@\\1", md)
  md <- gsub("\n{3,}", "\n\n", md)

  if (html == "index.html") {
    meta <- function(nombre) xml_attr(xml_find_first(doc, sprintf("//meta[@name='%s']", nombre)), "content")
    yaml <- c(
      "---",
      sprintf("title: %s", q(xml_text(xml_find_first(doc, "//title")))),
      sprintf("author: %s", q(meta("author"))),
      sprintf("date: %s", q(meta("date"))),
      "site: bookdown::bookdown_site",
      "documentclass: book",
      "bibliography: [references.bib]",
      "link-citations: yes",
      "lang: es",
      sprintf("description: %s", q(meta("description"))),
      "---",
      "",
      "```{r setup, include=FALSE}",
      "knitr::opts_chunk$set(echo = FALSE, message = FALSE, warning = FALSE)",
      "```",
      ""
    )
    md <- paste(c(yaml, md), collapse = "\n")
  }

  writeLines(enc2utf8(md), file.path(dst, capitulos[[html]]), useBytes = TRUE)
  cat(html, "->", capitulos[[html]], ":", length(bloques), "bloques\n")
}
