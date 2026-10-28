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
