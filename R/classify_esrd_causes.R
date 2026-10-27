# Purpose: draft the mapping of every primary-cause code (USRDS format
#   $PD96DET) to the six cause categories, by an ensemble of three large
#   language models, for review by the deciders (open decision #D4).
# Needs: setup.R and functions.R sourced first; API keys for the three
#   providers in .Renviron (OPENAI_API_KEY, ANTHROPIC_API_KEY, GEMINI_API_KEY).
# Produces: references/esrd-cause-categories.csv, with each model's category
#   and reason, whether they agree, and final_category (filled for unanimous
#   codes; the deciders fill the rest and their initials in reviewed_by).
# Run once, by hand, outside main.R: it makes paid API calls.
# Only the public code list from the USRDS Researcher's Guide is sent. No
#   patient data are sent, and the code list is not filtered by patient data.

## ---- load-cause-codes
# usRds holds Appendix C internally; usRds:::metadata_c is used until the
# package exports the formats (to be raised in the usRds project).
cause_codes <- usRds:::metadata_c[["PD96DET"]] |>
  transmute(
    code = str_trim(as.character(value)),
    description = str_squish(as.character(description))
  ) |>
  filter(code != "**OTHER**") |>
  distinct(code, .keep_all = TRUE)

## ---- define-classification-prompt
classification_prompt <- function(batch) {
  category_list <- str_flatten(str_c("- ", esrd_cause_categories), "\n")
  code_list <- str_flatten(str_c(batch$code, ": ", batch$description), "\n")

  str_glue(
    "You are a nephrologist classifying the primary cause of kidney failure recorded ",
    "on the CMS-2728 Medical Evidence form, using the USRDS code list.\n\n",
    "Assign each code to exactly one of these categories:\n",
    "{category_list}\n\n",
    "Use 'Other' for every cause that fits none of the first five, and for codes ",
    "meaning missing, unknown or unreconcilable. Classify from the code and its ",
    "description only; do not assume information that is not given.\n",
    "Return one entry per code, with the code exactly as given and a reason of ",
    "at most 15 words.\n\nCodes:\n",
    "{code_list}"
  )
}

classification_type <- ellmer::type_array(
  ellmer::type_object(
    code = ellmer::type_string("The code exactly as given"),
    category = ellmer::type_enum(esrd_cause_categories, "Cause of kidney failure category"),
    reason = ellmer::type_string("Reason, at most 15 words")
  )
)

## ---- classify-with-ensemble
providers <- list(
  openai = function() ellmer::chat_openai(model = esrd_classifier_models$openai),
  anthropic = function() ellmer::chat_anthropic(model = esrd_classifier_models$anthropic),
  google = function() ellmer::chat_google_gemini(model = esrd_classifier_models$google)
)

votes <- imap(providers, function(chat_fn, provider) {
  classify_codes(cause_codes, chat_fn, classification_prompt, classification_type,
                 batch_size = esrd_classifier_batch_size, provider = provider)
}) |>
  list_rbind()

# Every model must return every code exactly once, and no code that was not
# asked about
vote_problems <- cause_codes |>
  select(code) |>
  cross_join(tibble(provider = names(providers))) |>
  full_join(count(votes, provider, code), by = join_by(code, provider)) |>
  filter(is.na(n) | n != 1 | !code %in% cause_codes$code)

if (nrow(vote_problems) > 0) {
  stop(str_glue(
    "{nrow(vote_problems)} code and model pair(s) are missing, repeated or unknown."
  ), call. = FALSE)
}

## ---- measure-agreement
mapping <- ensemble_agreement(votes, cause_codes) |>
  mutate(
    final_category = model_category,
    reviewed_by = if_else(unanimous, "unanimous", NA_character_),
    classified_on = as.character(Sys.Date()),
    models = str_flatten(unlist(esrd_classifier_models), "; ")
  )

agreement <- mapping |>
  select(starts_with("category_")) |>
  irr::kappam.fleiss()

message(str_glue(
  "{sum(mapping$unanimous)} of {nrow(mapping)} codes unanimous; ",
  "Fleiss' kappa {round(agreement$value, 3)}. Review the others before running main.R."
))

## ---- write-mapping
write_csv(mapping, esrd_cause_mapping_file, na = "")
