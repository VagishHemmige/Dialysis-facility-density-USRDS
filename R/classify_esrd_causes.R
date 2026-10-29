# Purpose: draft the mapping of every primary-cause code (USRDS format
#   $PD96DET) to the six cause categories, by an ensemble of five large
#   language models, for review by the deciders (open decision #D4).
# Needs: setup.R and functions.R sourced first; the irr package (Fleiss'
#   kappa); API keys for the three cloud providers in .Renviron
#   (OPENAI_API_KEY, ANTHROPIC_API_KEY, GEMINI_API_KEY); Ollama running on this
#   computer with the two local models in setup.R pulled (ollama pull <model>).
# Produces: one file of checked answers per provider in esrd_votes_dir
#   (data-raw/, gitignored); esrd_cause_mapping_file (references/), with each
#   model's category and reason, how the models agreed, and final_category
#   (filled when at least esrd_classifier_min_agreement models agree; the
#   deciders fill the rest and their initials in `reviewer`);
#   esrd_cause_agreement_file, a one-row summary of agreement.
# Run once, by hand: it makes paid API calls, so its line in main.R (after
#   download_public_data.R) is commented out.
# Only the public code list from the USRDS Researcher's Guide is sent to the
#   cloud models; the local models receive the same list and send nothing
#   anywhere. No patient data are used, and the code list is not filtered by
#   patient data.

## ---- check-ellmer-version
# ellmer sends Claude a native structured-output request only for model names
# it recognizes; Claude 5 names (such as claude-sonnet-5-5) are recognized from
# ellmer 0.5.0 (has_claude_structured_output() in R/provider-claude.R). Older
# versions force a tool call instead, which current Claude models reject
# ("tool_choice ... not supported for this model").
if (packageVersion("ellmer") < "0.5.0") {
  stop(str_glue(
    "ellmer {packageVersion('ellmer')} is too old for the Claude model in setup.R. ",
    "Run install.packages(\"ellmer\") to get 0.5.0 or later."
  ), call. = FALSE)
}

## ---- protect-reviewed-mapping
# A rerun rewrites the mapping file. Stop before any API call if the deciders
# have already reviewed codes in it, so their review is not overwritten.
if (file.exists(esrd_cause_mapping_file)) {
  existing_mapping <- read_csv(
    esrd_cause_mapping_file,
    col_types = cols(.default = col_character())
  )
  # Files written before the `reviewer` column held the deciders' initials in
  # `reviewed_by`, beside the models' "unanimous" and "2 of 3 models"
  reviewed_codes <- if ("reviewer" %in% names(existing_mapping)) {
    filter(existing_mapping, !is.na(reviewer))
  } else {
    filter(
      existing_mapping,
      !is.na(reviewed_by),
      !str_detect(reviewed_by, "^unanimous$|of \\d+ models$")
    )
  }

  if (nrow(reviewed_codes) > 0) {
    stop(str_glue(
      "{esrd_cause_mapping_file} has {nrow(reviewed_codes)} code(s) reviewed by the deciders. ",
      "Rename or move it before rerunning, then copy the reviewed rows into the new file."
    ), call. = FALSE)
  }
}

## ---- load-cause-codes
# usRds holds Appendix C internally; usRds:::metadata_c is used until the
# package exports the formats (to be raised in the usRds project). The
# **OTHER** row is the format's catch-all for unlisted values, not a code.
cause_codes <- usRds:::metadata_c[["PD96DET"]] |>
  transmute(
    code = str_trim(as.character(value)),
    description = str_squish(as.character(description))
  ) |>
  filter(code != "**OTHER**")

# A code listed twice would be classified twice; stop rather than keep one
duplicated_codes <- cause_codes |>
  count(code) |>
  filter(n > 1)

if (nrow(duplicated_codes) > 0) {
  stop(str_glue(
    "$PD96DET lists {nrow(duplicated_codes)} code(s) more than once: ",
    "{str_flatten_comma(duplicated_codes$code)}."
  ), call. = FALSE)
}

## ---- define-classification-prompt
# The prompt is the text file esrd_classifier_prompt_file (prompts/), shown in
# full on the website. It defines each category in words; {{code_list}} is
# filled in for each batch.
prompt_text <- read_lines(esrd_classifier_prompt_file)

# The structured output can only return names from esrd_cause_categories, so
# the prompt must define each of them under exactly that name
undefined_categories <- esrd_cause_categories |>
  discard(\(category) any(str_starts(prompt_text, str_glue("- {category}:"))))

if (length(undefined_categories) > 0) {
  stop(str_glue(
    "{esrd_classifier_prompt_file} has no definition line ",
    "(\"- <category>: ...\") for: {str_flatten_comma(undefined_categories)}."
  ), call. = FALSE)
}

classification_prompt <- function(batch) {
  ellmer::interpolate_file(
    esrd_classifier_prompt_file,
    code_list = str_flatten(str_c(batch$code, ": ", batch$description), "\n")
  )
}

# A short fingerprint of the prompt text, ignoring Windows line endings. It is
# part of each saved answer file's name, so editing the prompt asks every
# provider again instead of reusing answers to the old prompt.
prompt_version <- prompt_text |>
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
# One function per model. Each takes a batch of codes and returns one row per
# code with code, category and reason, through ellmer's structured output.
# Each call starts a new chat, so no batch sees another batch's answers.
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

# The two local models run through Ollama (http://localhost:11434), in the
# same way; ask_ollama() returns the function for one of them
ask_ollama <- function(model) {
  function(batch) {
    chat <- ellmer::chat_ollama(model = model, echo = "none")
    chat$chat_structured(classification_prompt(batch), type = classification_type)
  }
}

providers <- list(
  openai = ask_openai,
  anthropic = ask_anthropic,
  google = ask_google,
  ollama_qwen = ask_ollama(esrd_classifier_models$ollama_qwen),
  ollama_granite = ask_ollama(esrd_classifier_models$ollama_granite)
)

## ---- classify-with-ensemble
# Each model's answers are saved in esrd_votes_dir under the provider, model
# and prompt version, so a rerun after a failure asks only the models with no
# saved file. Saved answers are checked again on every run (check_votes()),
# so a file that no longer matches the code list, for example after a usRds
# update, stops the script instead of being used; delete that file to ask
# the model again.
votes_path <- function(provider) {
  # Ollama names contain ":", which Windows does not allow in file names
  model <- str_replace_all(esrd_classifier_models[[provider]], "[^A-Za-z0-9._-]", "-")
  file.path(esrd_votes_dir, str_glue("{provider}-{model}-{prompt_version}.csv"))
}

# Before asking any model, check that Ollama is running and has the local
# models that still need to be asked
local_to_ask <- names(providers) |>
  keep(\(provider) str_starts(provider, "ollama_")) |>
  discard(\(provider) file.exists(votes_path(provider)))

if (length(local_to_ask) > 0) {
  installed <- tryCatch(
    ellmer::models_ollama()$id,
    error = function(e) {
      stop("Ollama is not running on this computer. Start it, then rerun.", call. = FALSE)
    }
  )
  not_pulled <- setdiff(unlist(esrd_classifier_models[local_to_ask]), installed)
  if (length(not_pulled) > 0) {
    stop(str_glue(
      "Ollama does not have {str_flatten_comma(not_pulled)}. ",
      "Run in a terminal: {str_flatten(str_c('ollama pull ', not_pulled), '; ')}"
    ), call. = FALSE)
  }
}

message(str_glue(
  "Classifying {nrow(cause_codes)} codes with {length(providers)} models. ",
  "Saved answers are reused; a model that has to be asked can take a minute ",
  "or more per batch."
))

votes <- providers |>
  imap(function(ask, provider) {
    message("\n", provider, " (", esrd_classifier_models[[provider]], ")")
    cached_votes(
      path = votes_path(provider),
      classify = function(partial_path) {
        classify_codes(
          cause_codes,
          ask,
          batch_size = esrd_classifier_batch_sizes[[provider]],
          label = provider,
          partial_path = partial_path
        )
      }
    ) |>
      check_votes(cause_codes, esrd_cause_categories, provider) |>
      mutate(provider = provider)
  }) |>
  list_rbind()

## ---- measure-agreement
mapping <- ensemble_agreement(votes, cause_codes, min_agreement = esrd_classifier_min_agreement) |>
  mutate(
    final_category = model_category,
    agreement = case_when(
      unanimous ~ "unanimous",
      !is.na(model_category) ~ str_glue("{n_agreeing} of {n_providers} models"),
      .default = "no majority"
    ),
    # Filled by the deciders for every code they review
    reviewer = NA_character_,
    prompt_version = prompt_version,
    ellmer_version = as.character(packageVersion("ellmer")),
    models = str_flatten(unlist(esrd_classifier_models), "; "),
    mapping_written_on = as.character(Sys.Date())
  )

# Fleiss' kappa describes how far the models agree beyond chance
# (1 = perfect, 0 = chance). It is reported, not used to accept codes.
kappa <- mapping |>
  select(starts_with("category_")) |>
  irr::kappam.fleiss()

agreement_summary <- tibble(
  codes = nrow(mapping),
  unanimous = sum(mapping$agreement == "unanimous"),
  majority_only = sum(!is.na(mapping$model_category) & mapping$agreement != "unanimous"),
  no_majority = sum(is.na(mapping$model_category)),
  fleiss_kappa = kappa$value,
  kappa_z = kappa$statistic,
  kappa_p_value = kappa$p.value,
  prompt_version = prompt_version,
  models = first(mapping$models),
  written_on = as.character(Sys.Date())
)

message(str_glue(
  "{agreement_summary$unanimous} of {agreement_summary$codes} codes unanimous, ",
  "{agreement_summary$majority_only} by majority only, ",
  "{agreement_summary$no_majority} with no majority; ",
  "Fleiss' kappa {round(agreement_summary$fleiss_kappa, 3)}. ",
  "Review the codes with no majority before running main.R."
))

## ---- write-mapping
# Both files hold only public codes, descriptions and model answers. Git keeps
# no empty folders, so references/ does not exist in a fresh copy until the
# first mapping is written and committed.
dir.create(dirname(esrd_cause_mapping_file), recursive = TRUE, showWarnings = FALSE)
write_csv(mapping, esrd_cause_mapping_file, na = "")
write_csv(agreement_summary, esrd_cause_agreement_file, na = "")
