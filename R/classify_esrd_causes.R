# Purpose: draft the mapping of every primary-cause code (USRDS format
#   $PD96DET) to the six cause categories, by an ensemble of three large
#   language models, for review by the deciders (open decision #D4).
# Needs: setup.R and functions.R sourced first; API keys for the three
#   providers in .Renviron (OPENAI_API_KEY, ANTHROPIC_API_KEY, GEMINI_API_KEY).
# Produces: one file of checked answers per provider in esrd_votes_dir
#   (data-raw/, gitignored); references/esrd-cause-categories.csv, with each model's category
#   and reason, whether they agree, and final_category (filled for unanimous
#   codes; the deciders fill the rest and their initials in reviewed_by).
# Run once, by hand, outside main.R: it makes paid API calls.
# Only the public code list from the USRDS Researcher's Guide is sent. No
#   patient data are sent, and the code list is not filtered by patient data.

## ---- check-ellmer-version
# ellmer 0.4.2 and later use Anthropic's own structured output for Claude 4.5
# and newer models. Earlier versions force a tool call instead, which current
# Claude models reject ("tool_choice ... not supported for this model").
# ellmer 0.5.0 and later also need Gemini 3 or newer for structured output.
if (packageVersion("ellmer") < "0.4.2") {
  stop(str_glue(
    "ellmer {packageVersion('ellmer')} is too old for the Claude model in setup.R. ",
    "Run install.packages(\"ellmer\") to get 0.4.2 or later."
  ), call. = FALSE)
}

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
# The prompt is the text file esrd_classifier_prompt_file (prompts/), shown in
# full on the website. {{category_list}} and {{code_list}} are filled in for
# each batch.
classification_prompt <- function(batch) {
  ellmer::interpolate_file(
    esrd_classifier_prompt_file,
    category_list = str_flatten(str_c("- ", esrd_cause_categories), "\n"),
    code_list = str_flatten(str_c(batch$code, ": ", batch$description), "\n")
  )
}

# A short fingerprint of the prompt text, ignoring Windows line endings. It is
# part of each saved answer file's name, so editing the prompt asks every
# provider again instead of reusing answers to the old prompt.
prompt_version <- esrd_classifier_prompt_file |>
  read_lines() |>
  str_remove_all("\r") |>
  rlang::hash() |>
  str_sub(1, 8)

classification_type <- ellmer::type_array(
  ellmer::type_object(
    code = ellmer::type_string("The code exactly as given"),
    category = ellmer::type_enum(esrd_cause_categories, "Cause of kidney failure category"),
    reason = ellmer::type_string("Reason, at most 15 words")
  )
)

## ---- define-providers
# One function per provider. Each takes a batch of codes and returns one row
# per code with code, category and reason, through ellmer's structured output.
# Every provider's answers then pass the same check (check_votes()).
ask_openai <- function(batch) {
  chat <- ellmer::chat_openai(model = esrd_classifier_models$openai, echo = "none")
  chat$chat_structured(classification_prompt(batch), type = classification_type)
}

ask_google <- function(batch) {
  chat <- ellmer::chat_google_gemini(model = esrd_classifier_models$google, echo = "none")
  chat$chat_structured(classification_prompt(batch), type = classification_type)
}

ask_anthropic <- function(batch) {
  chat <- ellmer::chat_anthropic(
    model = esrd_classifier_models$anthropic,
    params = ellmer::params(max_tokens = esrd_classifier_claude_max_tokens),
    echo = "none"
  )
  chat$chat_structured(classification_prompt(batch), type = classification_type)
}

providers <- list(
  openai = ask_openai,
  anthropic = ask_anthropic,
  google = ask_google
)

## ---- classify-with-ensemble
# Each provider is run and checked on its own, and its answers are saved in
# esrd_votes_dir under the provider, model and prompt version. If one provider
# fails, rerunning the script asks only the providers that have no saved file;
# changing a model in setup.R or the prompt file asks again.
votes <- providers |>
  imap(function(ask, provider) {
    cached_votes(
      path = file.path(
        esrd_votes_dir,
        str_glue("{provider}-{esrd_classifier_models[[provider]]}-{prompt_version}.csv")
      ),
      classify = function() {
        cause_codes |>
          classify_codes(ask, batch_size = esrd_classifier_batch_size) |>
          check_votes(cause_codes, esrd_cause_categories, provider)
      }
    ) |>
      mutate(provider = provider)
  }) |>
  list_rbind()

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
