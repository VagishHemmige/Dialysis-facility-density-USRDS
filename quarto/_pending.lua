-- Marks provisional content in yellow and explains the mark on pages that
-- have it (AGENTS.md, "Provisional content").
--
-- - A paragraph that starts with **Decision pending:** (study pages) or
--   **Open:** (the analysis plan) is wrapped in a `pending-note` block, with
--   no change to the page's source.
-- - Any span written as [text]{.pending} is marked where it stands.
-- - A page with at least one mark gets a Pending callout at the top that
--   explains the mark (styled by custom-callout, which runs after this).
--
-- Registered under `filters:` in _quarto.yml. The leading underscore keeps
-- Quarto from treating this file as a page.

-- Paragraphs that start with one of these bold labels are marked: the study
-- pages' notes on every page, and the analysis plan's own markers for open
-- points on the plan's page only (quarto/analysis-plan.qmd).
local LABELS = { "Decision pending:" }
local PLAN_LABELS = { "Decision pending:", "Open:" }

local function is_plan_page()
  local input = quarto.doc.input_file or ""
  return input:match("analysis%-plan%.qmd$") ~= nil
end

local SAMPLE = "Text highlighted like this"
local LEGEND = " is provisional: it depends on a decision the analysis plan " ..
  "has not yet made."

-- The comment button's label belongs to the issue-comments extension: its
-- `text: button:` setting, or the extension's default. Without the
-- extension (no `issue-comments:` block), the callout says nothing about
-- commenting.
local DEFAULT_BUTTON = "💬 Comment"

local function comment_sentence(meta)
  local ic = meta["issue-comments"]
  if ic == nil or ic["endpoint"] == nil then return nil end
  local label = DEFAULT_BUTTON
  if ic["text"] ~= nil and ic["text"]["button"] ~= nil then
    local s = pandoc.utils.stringify(ic["text"]["button"])
    if s ~= "" then label = s end
  end
  return " To comment on any part of this page, highlight the text and " ..
    "use the " .. label .. " button."
end

-- Accepts the colon inside or just after the bold (**Open:** or **Open**:).
local function starts_with_label(para, labels)
  local first = para.content[1]
  if first == nil or first.t ~= "Strong" then return false end
  local text = pandoc.utils.stringify(first)
  local after = para.content[2]
  local colon_after = after ~= nil and after.t == "Str"
    and after.text:sub(1, 1) == ":"
  for _, label in ipairs(labels) do
    if text == label then return true end
    if colon_after and text == label:sub(1, -2) then return true end
  end
  return false
end

-- On the plan's page, the plan's **Open:** marker may stand anywhere in a
-- paragraph ("marks the open point where it occurs"), so a paragraph that
-- contains it is marked too.
local function has_inline_open(para)
  for i, el in ipairs(para.content) do
    if el.t == "Strong" then
      local text = pandoc.utils.stringify(el)
      local after = para.content[i + 1]
      if text == "Open:" or (text == "Open" and after ~= nil
          and after.t == "Str" and after.text:sub(1, 1) == ":") then
        return true
      end
    end
  end
  return false
end

function Pandoc(doc)
  if not quarto.doc.is_format("html") then return doc end

  local marked = false
  local plan = is_plan_page()
  local labels = plan and PLAN_LABELS or LABELS

  local blocks = doc.blocks:walk({
    Para = function(para)
      if starts_with_label(para, labels) or (plan and has_inline_open(para)) then
        marked = true
        return pandoc.Div({ para }, pandoc.Attr("", { "pending-note" }))
      end
    end,
    Span = function(span)
      if span.classes:includes("pending") then marked = true end
    end,
  })

  if marked then
    local legend = pandoc.Div({
      pandoc.Header(3, { pandoc.Str("Provisional") }),
      pandoc.Para({
        pandoc.Span({ pandoc.Str(SAMPLE) }, pandoc.Attr("", { "pending" })),
        pandoc.Str(LEGEND .. (comment_sentence(doc.meta) or "")),
      }),
    }, pandoc.Attr("", { "Pending" }))
    blocks:insert(1, legend)
  end

  doc.blocks = blocks
  return doc
end
