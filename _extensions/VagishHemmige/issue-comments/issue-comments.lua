-- issue-comments: let readers highlight text and send a comment that is
-- filed as a GitHub issue by a Google Apps Script relay.
--
-- issue-comments:
--   endpoint: https://script.google.com/macros/s/XXXX/exec   # required
--   owner: Jane Doe              # who posts the issues; defaults to `author`
--   contact: https://...         # how readers reach you (URL or mailto:)
--   preview: true                # show the exact issue before posting
--   passcode: false              # ask readers for a shared passcode
--   page-button: false           # also show "Comment on this page"

local function str(v)
  if v == nil then return nil end
  local s = pandoc.utils.stringify(v)
  if s == "" then return nil end
  return s
end

local function bool(v, default)
  if v == nil then return default end
  if type(v) == "boolean" then return v end
  local s = pandoc.utils.stringify(v)
  return s == "true" or s == "yes"
end

-- `author` may be a string, a list, or a list of maps with `name`.
local function first_author(meta)
  local a = meta["author"]
  if type(a) == "table" and a[1] ~= nil then a = a[1] end
  if type(a) == "table" and a["name"] ~= nil then a = a["name"] end
  return str(a)
end

function Meta(meta)
  if not quarto.doc.is_format("html") then
    return meta
  end

  local cfg = meta["issue-comments"]
  if cfg == nil or cfg == false then
    return meta
  end
  if type(cfg) ~= "table" then
    quarto.log.warning("issue-comments: expected a map with at least `endpoint`.")
    return meta
  end

  local endpoint = str(cfg["endpoint"])
  if endpoint == nil then
    quarto.log.warning("issue-comments: no `endpoint` set; commenting is disabled.")
    return meta
  end

  local settings = {
    endpoint = endpoint,
    owner = str(cfg["owner"]) or first_author(meta),
    contact = str(cfg["contact"]),
    preview = bool(cfg["preview"], true),
    passcode = bool(cfg["passcode"], false),
    pageButton = bool(cfg["page-button"], false),
  }
  if settings.contact == nil then
    quarto.log.warning("issue-comments: no `contact` set; readers won't see how to reach you.")
  end

  quarto.doc.add_html_dependency({
    name = "issue-comments",
    version = "0.2.0",
    scripts = { "issue-comments.js" },
    stylesheets = { "issue-comments.css" },
  })

  -- Escape "</" so values cannot close the script tag.
  local json = quarto.json.encode(settings):gsub("</", "<\\/")
  quarto.doc.include_text("in-header",
    "<script>window.ISSUE_COMMENTS = " .. json .. ";</script>")

  return meta
end
