# Purpose: helpers used only by the website's pages, never by the analysis.
#   main.R does not source this file. These functions read only code or text
#   given to them, never data, and are the only code a page may run besides
#   the hidden knitr::read_chunk() import (AGENTS.md, "Quarto website").
# Needs: the packages are called with ::, so a page can source this file on
#   its own: source("_site_functions.R").

# Two versions of some code side by side: removed lines in red on the left,
# added lines in green on the right, unchanged lines aligned, and long
# unchanged stretches collapsed. `old` and `new` are the code itself, as text
# (one string with line breaks, or one string per line). The style is in
# styles.css (classes starting "sbs-").
side_by_side_diff <- function(old, new, old_title = "Before", new_title = "After", keep = 3) {
  as_lines <- function(code) {
    # A leading or trailing line break (as in a raw string) is not a line
    unlist(stringr::str_split(stringr::str_remove_all(code, "^\n|\n$"), "\n"))
  }
  old <- as_lines(old)
  new <- as_lines(new)

  # diffobj finds the shortest set of removals and additions turning old into new
  script <- as.data.frame(diffobj::ses_dat(old, new))

  # Number each line on its own side, then pair the removed and added lines
  # within each run of changes
  lines <- tibble::tibble(op = as.character(script$op), text = script$val) |>
    dplyr::mutate(
      old_no = dplyr::if_else(op != "Insert", cumsum(op != "Insert"), NA_integer_),
      new_no = dplyr::if_else(op != "Delete", cumsum(op != "Delete"), NA_integer_),
      run = dplyr::consecutive_id(op == "Match")
    )

  pair_run <- function(run_lines, key) {
    if (dplyr::first(run_lines$op) == "Match") {
      return(dplyr::transmute(
        run_lines,
        old_no, old_text = text, new_no, new_text = text, changed = FALSE
      ))
    }
    removed <- dplyr::filter(run_lines, op == "Delete")
    added <- dplyr::filter(run_lines, op == "Insert")
    rows <- seq_len(max(nrow(removed), nrow(added)))
    tibble::tibble(
      old_no = removed$old_no[rows],
      old_text = removed$text[rows],
      new_no = added$new_no[rows],
      new_text = added$text[rows],
      changed = TRUE
    )
  }

  rows <- lines |>
    dplyr::group_by(run) |>
    dplyr::group_modify(pair_run) |>
    dplyr::mutate(
      run_length = dplyr::n(),
      position = dplyr::row_number(),
      hidden = !changed & run_length > 2 * keep + 2 &
        position > keep & position <= run_length - keep
    ) |>
    dplyr::ungroup() |>
    dplyr::mutate(gap = hidden & !dplyr::lag(hidden, default = FALSE)) |>
    dplyr::filter(!hidden | gap)

  cell <- function(number, text, class) {
    if (is.na(number)) {
      return('<td class="sbs-no"></td><td class="sbs-empty"></td>')
    }
    shown <- if (text == "") "&nbsp;" else htmltools::htmlEscape(text)
    stringr::str_glue('<td class="sbs-no">{number}</td><td class="sbs-code {class}">{shown}</td>')
  }

  row_html <- function(old_no, old_text, new_no, new_text, changed, gap, run_length, ...) {
    if (gap) {
      return(stringr::str_glue(
        '<tr class="sbs-gap"><td colspan="4">{run_length - 2 * keep} unchanged lines</td></tr>'
      ))
    }
    stringr::str_c(
      "<tr>",
      cell(old_no, old_text, if (changed) "sbs-del" else ""),
      cell(new_no, new_text, if (changed) "sbs-add" else ""),
      "</tr>"
    )
  }

  body <- purrr::pmap_chr(rows, row_html)

  htmltools::HTML(stringr::str_c(
    '<div class="sbs-wrap"><table class="sbs">',
    '<colgroup><col class="sbs-n"><col><col class="sbs-n"><col></colgroup>',
    stringr::str_glue(
      '<thead><tr><th colspan="2">{old_title}</th><th colspan="2">{new_title}</th></tr></thead>'
    ),
    "<tbody>",
    stringr::str_flatten(body),
    "</tbody></table></div>"
  ))
}

# An R Markdown file as page content, without running it: the prose is
# formatted as it would be in the knitted file, and each code chunk becomes a
# syntax-highlighted code block headed by its number, label, options and line
# numbers in the file (every chunk is shown, including eval = FALSE and
# include = FALSE ones). The YAML header is shown as a code block. Inline R
# code is never evaluated; it can only appear as text. `path` is the .Rmd
# file. `fold` sets how the blocks start: "closed" or "open" makes each one
# foldable under its header, in the same element Quarto uses for code-fold,
# so the page's "Show All Code" and "Hide All Code" menu items act on them;
# "none" shows them as plain blocks. Use the result in a chunk with
# `output: asis`.
rmd_as_markdown <- function(path, fold = c("closed", "open", "none")) {
  fold <- match.arg(fold)
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  starts <- stringr::str_detect(lines, "^\\s*```+\\s*\\{r")
  ends <- stringr::str_detect(lines, "^\\s*```+\\s*$")

  # A code block fenced by more backticks than any run inside it, without
  # blank lines at either end, under its title
  block <- function(code, language, title) {
    runs <- stringr::str_extract_all(code, "`+") |> unlist() |> nchar()
    fence <- strrep("`", max(c(3, runs + 1)))
    code <- code[cumsum(code != "") > 0]
    code <- rev(rev(code)[cumsum(rev(code) != "") > 0])
    if (fold == "none") {
      title <- stringr::str_replace_all(title, '"', "'")
      return(c("", stringr::str_glue('{fence}{{.{language} filename="{title}"}}'), code, fence, ""))
    }
    c(
      "",
      stringr::str_glue('<details class="code-fold"{if (fold == "open") " open" else ""}>'),
      stringr::str_glue("<summary>{htmltools::htmlEscape(title)}</summary>"),
      "",
      stringr::str_glue("{fence}{{.{language}}}"),
      code,
      fence,
      "",
      "</details>",
      ""
    )
  }

  out <- character()
  i <- 1
  # The YAML header, if the file starts with one
  if (length(lines) > 0 && lines[1] == "---") {
    close <- which(lines[-1] %in% c("---", "..."))[1] + 1
    if (is.na(close)) stop("The YAML header in ", path, " is never closed.")
    out <- block(lines[2:(close - 1)], "yaml", stringr::str_glue("YAML header (lines 1-{close})"))
    i <- close + 1
  }

  chunk <- 0
  while (i <= length(lines)) {
    if (!starts[i]) {
      out <- c(out, lines[i])
      i <- i + 1
      next
    }
    close <- which(ends & seq_along(lines) > i)[1]
    if (is.na(close)) stop("The chunk starting on line ", i, " of ", path, " is never closed.")
    chunk <- chunk + 1
    header <- lines[i] |>
      stringr::str_remove("^\\s*```+\\s*\\{r[ ,]*") |>
      stringr::str_remove("\\}\\s*$") |>
      stringr::str_squish()
    # The label is the first option if it has no "="; spaces are allowed
    parts <- stringr::str_split_1(header, "\\s*,\\s*") |> purrr::discard(\(x) x == "")
    label <- if (length(parts) > 0 && !stringr::str_detect(parts[1], "=")) parts[1] else NA
    options <- if (is.na(label)) parts else parts[-1]
    # For example "Chunk 21: models1, eval=FALSE (lines 1737-2131)"; plain
    # ASCII, so it shows the same under any locale
    title <- stringr::str_glue(
      "Chunk {chunk}",
      if (length(parts) > 0) ": " else "",
      stringr::str_flatten(c(if (!is.na(label)) label, options), ", "),
      " (lines {i}-{close})"
    )
    out <- c(out, block(lines[seq_len(close - i - 1) + i], "r", title))
    i <- close + 1
  }
  stringr::str_flatten(out, "\n")
}
