# Purpose: assign every primary-cause code (USRDS format $PD96DET) to its
#   USRDS primary disease group: USRDS's own assignment where it has one, and
#   otherwise an ensemble of three large language models, for review by the
#   deciders (open decision #D4). The paper's six categories follow from the
#   groups through references/usrds-cause-groups.csv.
# Needs: setup.R and functions.R sourced first; API keys for the three
#   providers in .Renviron (OPENAI_API_KEY, ANTHROPIC_API_KEY, GEMINI_API_KEY).
# Produces: one file of checked answers per provider in esrd_votes_dir
#   (data-raw/, gitignored); references/esrd-cause-categories.csv, with each
#   code's USRDS primary disease group: USRDS's own where it has one,
#   otherwise each model's group and reason, whether they agree, and
#   final_group (filled when USRDS or all three models give it; the deciders
#   fill the rest and their initials in reviewed_by).
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
# Every primary-cause code (format $PD96DET) with its description and coding
# system, and the USRDS primary disease group where USRDS assigns one (format
# PD_SUBGROUP, mostly ICD-10-CM codes). usRds holds Appendix C internally;
# usRds:::metadata_c is used until the package exports the formats.
cause_groups <- read_csv(esrd_cause_groups_file, col_types = cols(.default = col_character()))

usrds_code_groups <- usRds:::metadata_c[["PD_SUBGROUP"]] |>
  transmute(
    code = str_trim(as.character(value)),
    # Subgroups are a two-digit group and a letter ("03F"); one is written "9F"
    usrds_group = str_pad(str_extract(as.character(description), "^[0-9]+"), 2, pad = "0")
  ) |>
  left_join(select(cause_groups, usrds_group, group_name), by = "usrds_group") |>
  select(code, usrds_group_name = group_name)

cause_codes <- usRds:::metadata_c[["PD96DET"]] |>
  transmute(
    code = str_trim(as.character(value)),
    description = str_squish(as.character(description))
  ) |>
  filter(code != "**OTHER**", code != "") |>
  distinct(code, .keep_all = TRUE) |>
  mutate(code_system = cause_code_system(code)) |>
  left_join(usrds_code_groups, by = "code", relationship = "one-to-one")

# Codes USRDS has grouped are the reference; the models group the others
reference_codes <- filter(cause_codes, !is.na(usrds_group_name))
codes_to_classify <- filter(cause_codes, is.na(usrds_group_name))

## ---- define-classification-prompt
# The prompt is the text file esrd_classifier_prompt_file (prompts/), shown in
# full on the website. For each batch, {{group_list}} becomes the USRDS groups,
# {{reference_list}} the codes USRDS has grouped, and {{code_list}} the batch.
describe_code <- function(codes) {
  str_glue("{codes$code} [{codes$code_system}]: {codes$description}")
}

group_list <- cause_groups |>
  str_glue_data("- {group_name}: for example, {examples}") |>
  str_flatten("\n")

reference_list <- reference_codes |>
  arrange(usrds_group_name, code) |>
  mutate(line = str_glue("{describe_code(pick(everything()))} -> {usrds_group_name}")) |>
  pull(line) |>
  str_flatten("\n")

classification_prompt <- function(batch) {
  ellmer::interpolate_file(
    esrd_classifier_prompt_file,
    group_list = group_list,
    reference_list = reference_list,
    code_list = str_flatten(describe_code(batch), "\n")
  )
}

classification_type <- ellmer::type_array(
  ellmer::type_object(
    code = ellmer::type_string("The code exactly as given"),
    category = ellmer::type_enum(cause_groups$group_name, "USRDS primary disease group"),
    reason = ellmer::type_string("Reason, at most 15 words")
  )
)

# A short fingerprint of the prompt text, ignoring Windows line endings. It is
# part of each saved answer file's name, so editing the prompt asks every
# provider again instead of reusing answers to the old prompt.
prompt_version <- esrd_classifier_prompt_file |>
  read_lines() |>
  str_remove_all("\r") |>
  rlang::hash() |>
  str_sub(1, 8)

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
        codes_to_classify |>
          classify_codes(ask, batch_size = esrd_classifier_batch_size) |>
          check_votes(codes_to_classify, cause_groups$group_name, provider)
      }
    ) |>
      mutate(provider = provider)
  }) |>
  list_rbind()

## ---- measure-agreement
# One row per code. A code USRDS has grouped keeps that group. For the others,
# the group is accepted when all three models agree; the deciders fill
# final_group for the rest. The paper's category follows from the group
# (references/usrds-cause-groups.csv, read in link_area_data.R).
model_groups <- ensemble_agreement(votes, codes_to_classify) |>
  rename(model_group = model_category)

mapping <- cause_codes |>
  left_join(
    select(model_groups, -description, -code_system, -usrds_group_name),
    by = "code",
    relationship = "one-to-one"
  ) |>
  mutate(
    final_group = coalesce(usrds_group_name, model_group),
    reviewed_by = case_when(
      !is.na(usrds_group_name) ~ "USRDS",
      unanimous ~ "unanimous",
      .default = NA_character_
    ),
    classified_on = as.character(Sys.Date()),
    models = str_flatten(unlist(esrd_classifier_models), "; "),
    prompt_version = prompt_version
  )

agreement <- model_groups |>
  select(starts_with("category_")) |>
  irr::kappam.fleiss()

message(str_glue(
  "{nrow(reference_codes)} codes grouped by USRDS; ",
  "{sum(model_groups$unanimous)} of {nrow(model_groups)} others unanimous; ",
  "Fleiss' kappa {round(agreement$value, 3)}. Review the others before running main.R."
))

## ---- write-mapping
write_csv(mapping, esrd_cause_mapping_file, na = "")
