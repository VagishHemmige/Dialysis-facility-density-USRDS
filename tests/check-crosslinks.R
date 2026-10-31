# check-crosslinks.R: checks the cross-references between the functions page
# and the method pages against the code. Reads code and .qmd files only, never
# data. Run from the project root:
#
#   Rscript tests/check-crosslinks.R check   # report anything wrong; exit 1 if so
#   Rscript tests/check-crosslinks.R draft   # print what each section should carry
#
# The publish workflow runs `check` on every pull request. When it fails, run
# `draft` and copy the printed elements into the pages; never edit the prose
# around them to make the check pass.
#
# What each section carries (AGENTS.md, "Quarto website"):
#   quarto/functions.qmd, each function's section:
#     - `fn()` on the line under the heading: the function the chunk shows.
#     - **Used in the analysis:** the method-page sections that call it. One
#       place is a single line; more than one is a list with one item per page.
#     - **Called by:** the functions on this page that call it.
#   each method page, each section whose code calls a helper:
#     - **Functions used:** the helpers it calls, linked to their sections.
#   The labelled lines go after the prose, just before the code chunk.
#   R/functions.R has one top-level function per labelled chunk; a helper
#   defined inside another function belongs to that function.
#
# How calls are found: a function counts as used in a labelled section of an
# R/ script when its name appears there as code, called or passed by name
# (purrr::map(x, any_yes)). Comments and strings are ignored. Page anchors come
# from the .qmd headings (an explicit {#id}, otherwise Pandoc's identifier), so
# no render is needed.
#
# Limitations: a function called through its name as text (do.call("fn", ...),
# match.fun("fn"), get("fn")) is not found; neither is a call made through S3
# dispatch, or code outside a labelled section. R/main.R is not read. Raw
# strings (r"(...)") are read as code, so a helper named inside one would count
# as a use. Calls are matched by name only, so a local variable with a helper's
# name would also count as a use. A section that is not shown on any page (for
# example a script shown whole with `file:`) is reported, and links to and from
# it are skipped.

# Read every file as UTF-8, whatever the system locale
read_utf8 <- function(path, n = -1L) readLines(path, n = n, warn = FALSE, encoding = "UTF-8")

args <- commandArgs(trailingOnly = TRUE)
mode <- if (length(args)) args[1] else "draft"
stopifnot(mode %in% c("draft", "check"))

functions_script <- "R/functions.R"
functions_page <- "quarto/functions.qmd"
label_pattern <- "^\\s*##\\s*-{4}\\s*([^ -][^ ]*)\\s*-*\\s*$"

# ---- reading scripts --------------------------------------------------------

# Drop comments, keeping # inside strings
strip_comment <- function(line) {
  chars <- strsplit(line, "")[[1]]
  quote <- ""
  for (i in seq_along(chars)) {
    ch <- chars[i]
    if (quote == "") {
      if (ch %in% c("\"", "'", "`")) quote <- ch
      else if (ch == "#") return(paste(chars[seq_len(i - 1)], collapse = ""))
    } else if (ch == quote && (i == 1 || chars[i - 1] != "\\")) {
      quote <- ""
    }
  }
  line
}

# Blank out string contents, so names inside strings are not calls
strip_strings <- function(text) gsub("\"([^\"\\\\]|\\\\.)*\"|'([^'\\\\]|\\\\.)*'", "\"\"", text, perl = TRUE)

# Labelled sections of a script: label -> code with comments and strings removed
script_sections <- function(path) {
  lines <- read_utf8(path)
  starts <- grep(label_pattern, lines, perl = TRUE)
  labels <- sub(label_pattern, "\\1", lines[starts], perl = TRUE)
  ends <- c(starts[-1] - 1, length(lines))
  code <- mapply(function(s, e) {
    body <- if (e > s) lines[(s + 1):e] else character()
    strip_strings(paste(vapply(body, strip_comment, ""), collapse = "\n"))
  }, starts, ends)
  stats::setNames(as.list(code), labels)
}

# Top-level functions defined in each labelled section of R/functions.R
defined_functions <- function(sections) {
  lapply(sections, function(code) {
    lines <- strsplit(code, "\n")[[1]]
    depth <- 0
    found <- character()
    for (line in lines) {
      m <- regmatches(line, regexec("^\\s*([A-Za-z.][A-Za-z0-9._]*)\\s*(<-|=)\\s*function\\b", line, perl = TRUE))[[1]]
      if (length(m) && depth == 0) found <- c(found, m[2])
      depth <- depth + lengths(regmatches(line, gregexpr("\\{", line))) -
        lengths(regmatches(line, gregexpr("\\}", line)))
    }
    found
  })
}

uses_name <- function(code, name) {
  grepl(paste0("(?<![A-Za-z0-9._$@:])", gsub(".", "\\.", name, fixed = TRUE), "(?![A-Za-z0-9._])"), code, perl = TRUE)
}

# ---- reading pages ----------------------------------------------------------

# Pandoc's automatic identifier for a heading
pandoc_id <- function(text) {
  text <- gsub("`|\\*|_(?=\\w)|(?<=\\w)_", "", text, perl = TRUE)
  text <- gsub("\\[([^]]*)\\]\\([^)]*\\)", "\\1", text)
  text <- tolower(text)
  text <- gsub("[^[:alnum:] _.-]", "", text)
  text <- gsub("\\s+", "-", trimws(text))
  text <- sub("^[^[:alpha:]]+", "", text)
  if (text == "") "section" else text
}

# Every chunk label on a page, with its level-2 heading and anchor
page_sections <- function(path) {
  lines <- read_utf8(path)
  heading <- NA_character_
  anchor <- NA_character_
  seen <- character()
  out <- data.frame(label = character(), heading = character(), anchor = character(), line = integer())
  in_chunk <- FALSE
  for (i in seq_along(lines)) {
    line <- lines[i]
    if (grepl("^```", line)) in_chunk <- !in_chunk && grepl("^```\\{", line)
    if (!in_chunk && grepl("^##\\s+", line) && !grepl("^###", line)) {
      raw <- sub("^##\\s+", "", line)
      explicit <- regmatches(raw, regexec("\\{#([^ }]+)[^}]*\\}\\s*$", raw))[[1]]
      heading <- trimws(sub("\\s*\\{[^}]*\\}\\s*$", "", raw))
      anchor <- if (length(explicit)) explicit[2] else pandoc_id(heading)
      if (!length(explicit)) {
        base <- anchor
        n <- sum(seen == base)
        if (n) anchor <- paste0(base, "-", n)
        seen <- c(seen, base)
      }
    }
    m <- regmatches(line, regexec("^#\\|\\s*label:\\s*(\\S+)", line))[[1]]
    if (length(m) && !is.na(heading)) {
      out[nrow(out) + 1, ] <- list(m[2], heading, anchor, i)
    }
  }
  out
}

# Page titles as the sidebar shows them (this needs yaml, which rmarkdown
# installs), else the page's own title; also
# records the sidebar order in `sidebar_order`
sidebar_order <- character()
page_titles <- function(pages) {
  titles <- stats::setNames(rep(NA_character_, length(pages)), pages)
  if (file.exists("_quarto.yml") && requireNamespace("yaml", quietly = TRUE)) {
    walk <- function(x) {
      if (is.list(x)) {
        if (!is.null(x$href)) {
          href <- sub("^/", "", x$href)
          sidebar_order <<- c(sidebar_order, href)
          if (!is.null(x$text) && href %in% pages) titles[href] <<- x$text
        }
        for (y in x) walk(y)
      }
    }
    walk(yaml::yaml.load(paste(read_utf8("_quarto.yml"), collapse = "\n")))
  }
  for (p in pages[is.na(titles)]) {
    front <- read_utf8(p, n = 20)
    t <- grep("^title:", front, value = TRUE)
    titles[p] <- if (length(t)) gsub("^title:\\s*[\"']?|[\"']\\s*$", "", t[1]) else basename(p)
  }
  titles
}

# ---- building the map -------------------------------------------------------

fn_sections <- script_sections(functions_script)
fn_defined <- defined_functions(fn_sections)
fn_label <- stats::setNames(rep(names(fn_defined), lengths(fn_defined)), unlist(fn_defined))

scripts <- setdiff(list.files("R", pattern = "\\.R$", full.names = TRUE), "R/main.R")
pages <- list.files("quarto", pattern = "\\.qmd$", full.names = TRUE)
page_map <- do.call(rbind, lapply(pages, function(p) {
  s <- page_sections(p)
  if (nrow(s)) cbind(page = p, s) else NULL
}))
if (is.null(page_map)) page_map <- data.frame(page = character(), label = character(), heading = character(), anchor = character(), line = integer())
titles <- page_titles(pages)
where <- function(label) page_map[page_map$label == label, , drop = FALSE][1, ]

problems <- character()
problem <- function(...) problems <<- c(problems, paste0(...))

# Every use: function -> (script, label) that calls it
uses <- do.call(rbind, lapply(scripts, function(path) {
  secs <- script_sections(path)
  do.call(rbind, lapply(names(secs), function(lab) {
    called <- names(fn_label)[vapply(names(fn_label), function(f) uses_name(secs[[lab]], f), logical(1))]
    if (path == functions_script) called <- setdiff(called, fn_defined[[lab]])
    if (length(called)) data.frame(fn = called, script = path, label = lab) else NULL
  }))
}))

if (is.null(uses)) uses <- data.frame(fn = character(), script = character(), label = character())

# A helper's own chunk and the chunks that use it must each have a page section
for (lab in unique(c(unname(fn_label), uses$label))) {
  if (!lab %in% page_map$label) problem("chunk `", lab, "` is not shown on any page, so links to and from it are skipped")
}

link <- function(page, anchor, from_page) {
  target <- if (page == from_page) "" else basename(page)
  paste0(target, "#", anchor)
}

# Each entry is one element a section must carry, just before its code chunk
# (the function name goes first, just under the heading instead):
#   kind "name"      `fn()` on the functions page, under the heading
#   kind "analysis"  **Used in the analysis:** on the functions page
#   kind "called"    **Called by:** on the functions page
#   kind "uses"      **Functions used:** on a method page
expected <- list()
add <- function(page, label, heading, kind, text) {
  expected[[length(expected) + 1]] <<- list(page = page, label = label, heading = heading, kind = kind, text = text)
}
labels_of <- c(name = "", analysis = "**Used in the analysis:**", called = "**Called by:**", uses = "**Functions used:**")
section_line <- function(l) page_map$line[match(l, page_map$label)]

for (lab in names(fn_defined)) {
  home <- where(lab)
  if (is.na(home$page)) next
  fns <- fn_defined[[lab]]
  add(home$page, lab, home$heading, "name", paste0("`", fns, "()`", collapse = ", "))

  u <- uses[uses$fn %in% fns, , drop = FALSE]
  if (!nrow(u)) next
  places <- unique(do.call(rbind, lapply(unique(u$label), function(l) cbind(label = l, where(l)[, c("page", "heading", "anchor")]))))
  places <- places[!is.na(places$page), , drop = FALSE]

  # Analysis uses: method pages in sidebar order, sections in page order
  a <- places[places$page != functions_page, , drop = FALSE]
  if (nrow(a)) {
    a <- a[order(match(a$page, c(sidebar_order, pages)), section_line(a$label)), , drop = FALSE]
    groups <- vapply(unique(a$page), function(p) {
      rows <- a[a$page == p, , drop = FALSE]
      paste0(titles[[p]], ": ", paste0("[", rows$heading, "](", basename(p), "#", rows$anchor, ")", collapse = ", "))
    }, "")
    text <- if (length(groups) == 1) {
      paste0(labels_of[["analysis"]], " ", groups, ".")
    } else {
      # A page number at the start of a list item would start a numbered list
      paste0(labels_of[["analysis"]], "\n\n", paste0("-   ", sub("^(\\d+)\\.", "\\1\\\\.", groups), collapse = "\n"))
    }
    add(home$page, lab, home$heading, "analysis", text)
  }

  # Helper-to-helper calls: name the calling function
  h <- places[places$page == functions_page, , drop = FALSE]
  if (nrow(h)) {
    h <- h[order(section_line(h$label)), , drop = FALSE]
    callers <- vapply(h$label, function(l) fn_defined[[l]][1], "")
    add(home$page, lab, home$heading, "called",
        paste0(labels_of[["called"]], " ", paste0("[`", callers, "()`](#", h$anchor, ")", collapse = ", "), "."))
  }
}

for (lab in unique(uses$label[uses$script != functions_script])) {
  sec <- where(lab)
  if (is.na(sec$page)) next
  fns <- uses$fn[uses$label == lab]
  fns <- fns[order(match(fns, names(fn_label)))]
  fns <- fns[vapply(fns, function(f) !is.na(where(fn_label[[f]])$page), logical(1))]
  if (!length(fns)) next
  links <- vapply(fns, function(f) {
    target <- where(fn_label[[f]])
    paste0("[`", f, "()`](", basename(target$page), "#", target$anchor, ")")
  }, "")
  add(sec$page, lab, sec$heading, "uses", paste0(labels_of[["uses"]], " ", paste(links, collapse = ", "), "."))
}

# One top-level function per chunk
for (lab in names(fn_defined)) {
  if (length(fn_defined[[lab]]) > 1) {
    problem("R/functions.R chunk `", lab, "` defines ", length(fn_defined[[lab]]),
            " functions (", paste0(fn_defined[[lab]], "()", collapse = ", "), "); give each its own chunk")
  }
}

# ---- output -----------------------------------------------------------------

# The lines of a section between its heading and its chunk
section_body <- function(page, label) {
  lines <- read_utf8(page)
  chunk_line <- page_map$line[page_map$page == page & page_map$label == label][1]
  start <- max(c(0, grep("^##\\s", lines[seq_len(chunk_line)])))
  list(lines = lines[(start + 1):(chunk_line - 2)], offset = start)
}

# One element of a section: a bold-labelled line, plus its list if it has one
element_at <- function(body, i) {
  j <- i
  while (j < length(body) && !grepl("^(\\*\\*|```|`[A-Za-z.][A-Za-z0-9._]*\\(\\)`)", body[j + 1])) j <- j + 1
  block <- body[i:j]
  block <- block[seq_len(max(which(nzchar(trimws(block)))))]
  paste(sub("\\s+$", "", block), collapse = "\n")
}

if (mode == "draft") {
  for (e in expected) cat(e$page, " | ", e$heading, " (chunk `", e$label, "`)\n", e$text, "\n\n", sep = "")
  if (length(problems)) cat("Problems to fix first:\n", paste0("- ", problems, "\n"), sep = "")
} else {
  for (e in expected) {
    body <- section_body(e$page, e$label)$lines
    if (e$kind == "name") {
      first <- body[nzchar(trimws(body))][1]
      if (!identical(trimws(first), e$text)) problem(e$page, " / ", e$heading, ": the line under the heading should be ", e$text, ", found: ", first)
      next
    }
    at <- which(startsWith(body, labels_of[[e$kind]]))
    if (!length(at)) problem(e$page, " / ", e$heading, ": missing ", labels_of[[e$kind]])
    else if (!identical(element_at(body, at[1]), e$text)) {
      problem(e$page, " / ", e$heading, ": ", labels_of[[e$kind]], " is out of date\n    expected: ",
              gsub("\n", "\n              ", e$text), "\n    found:    ", gsub("\n", "\n              ", element_at(body, at[1])))
    }
  }
  # Labelled lines that should not be there, and links to sections that do not exist
  for (p in pages) {
    lines <- read_utf8(p)
    for (i in grep("^\\*\\*(Used in[^*]*|Called by|Functions used):\\*\\*", lines)) {
      kind <- names(labels_of)[match(sub("^(\\*\\*[^*]+\\*\\*).*", "\\1", lines[i]), labels_of)]
      sec <- page_map[page_map$page == p & page_map$line > i, , drop = FALSE][1, ]
      wanted <- any(vapply(expected, function(e) e$page == p && identical(e$label, sec$label) && identical(e$kind, kind), logical(1)))
      if (!wanted) problem(p, " line ", i, ": ", sub("^(\\*\\*[^*]+\\*\\*).*", "\\1", lines[i]), " should not be here")
      block <- element_at(lines, i)
      for (t in sub("^\\]\\((.*)\\)$", "\\1", regmatches(block, gregexpr("\\]\\(([^)]*)\\)", block))[[1]])) {
        target_page <- if (startsWith(t, "#")) p else file.path("quarto", sub("#.*", "", t))
        if (!sub(".*#", "", t) %in% page_map$anchor[page_map$page == target_page]) problem(p, " line ", i, ": link ", t, " points to no section")
      }
    }
  }
  if (length(problems)) {
    cat(paste0("- ", problems, "\n"), sep = "")
    quit(status = 1)
  }
  cat("Cross-references match the code: ", length(expected), " elements checked.\n", sep = "")
}
