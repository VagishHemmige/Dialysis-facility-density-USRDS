# Tests for quarto/_site_functions.R, the helpers used only by the website.
# Run from the project root: testthat::test_file("tests/test-site-functions.R")

library(testthat)
source(if (file.exists("quarto/_site_functions.R")) "quarto/_site_functions.R" else "../quarto/_site_functions.R")

cells <- function(html, class) {
  regmatches(html, gregexpr(paste0('class="sbs-code ', class, '">[^<]*'), html))[[1]] |>
    sub(pattern = '.*">', replacement = "")
}

test_that("side_by_side_diff marks removed and added lines and keeps matches", {
  html <- as.character(side_by_side_diff("a\nb\nc", "a\nx\nc"))
  expect_equal(cells(html, "sbs-del"), "b")
  expect_equal(cells(html, "sbs-add"), "x")
  expect_equal(cells(html, " *"), c("a", "a", "c", "c"))
})

test_that("side_by_side_diff ignores the line breaks around a raw string", {
  html <- as.character(side_by_side_diff("\na\nb\n", "\na\nb\n"))
  expect_false(grepl("sbs-del|sbs-add", html))
  expect_equal(lengths(regmatches(html, gregexpr("<tr><td", html))), 2)
})

test_that("side_by_side_diff collapses long unchanged stretches", {
  same <- paste(letters[1:20], collapse = "\n")
  html <- as.character(side_by_side_diff(paste0(same, "\nold"), paste0(same, "\nnew"), keep = 3))
  expect_match(html, "14 unchanged lines")
})

test_that("side_by_side_diff escapes code", {
  html <- as.character(side_by_side_diff("x <- a < b", "x <- a > b"))
  expect_match(html, "a &lt; b")
  expect_match(html, "a &gt; b")
})

rmd_file <- function(...) {
  path <- tempfile(fileext = ".Rmd")
  writeLines(c(...), path)
  path
}

test_that("rmd_as_markdown keeps prose and turns chunks into labelled code blocks", {
  md <- rmd_as_markdown(
    rmd_file(
      "---", "title: \"Test\"", "---", "", "Some *prose*.", "",
      "```{r load data, eval=FALSE}", "", "x <- 1", "", "```", "",
      "```{r}", "y <- 2", "```"
    ),
    fold = "none"
  )
  expect_match(md, "```{.yaml filename=\"YAML header (lines 1-3)\"}\ntitle: \"Test\"\n```", fixed = TRUE)
  expect_match(md, "\nSome *prose*.\n", fixed = TRUE)
  expect_match(md, "```{.r filename=\"Chunk 1: load data, eval=FALSE (lines 7-11)\"}\nx <- 1\n```", fixed = TRUE)
  expect_match(md, "```{.r filename=\"Chunk 2 (lines 13-15)\"}\ny <- 2\n```", fixed = TRUE)
  expect_no_match(md, "```{r", fixed = TRUE)
})

test_that("rmd_as_markdown folds each block under its header, closed or open", {
  path <- rmd_file("```{r a<b}", "x <- 1", "```")
  closed <- rmd_as_markdown(path)
  expect_match(closed, '<details class="code-fold">\n<summary>Chunk 1: a&lt;b (lines 1-3)</summary>\n\n```{.r}\nx <- 1\n```\n\n</details>', fixed = TRUE)
  expect_match(rmd_as_markdown(path, fold = "open"), '<details class="code-fold" open>', fixed = TRUE)
  expect_no_match(rmd_as_markdown(path, fold = "none"), "<details", fixed = TRUE)
})

test_that("rmd_as_markdown fences chunks that contain backticks", {
  md <- rmd_as_markdown(rmd_file("```{r}", "cat('```')", "```"))
  expect_match(md, "````{.r}", fixed = TRUE)
  expect_match(md, "\n````\n", fixed = TRUE)
})

test_that("rmd_as_markdown works without a YAML header and stops on an unclosed chunk", {
  expect_equal(rmd_as_markdown(rmd_file("Just prose.")), "Just prose.")
  expect_error(rmd_as_markdown(rmd_file("```{r}", "x <- 1")), "never closed")
})
