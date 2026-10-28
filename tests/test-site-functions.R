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
