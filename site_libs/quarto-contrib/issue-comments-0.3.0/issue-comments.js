/* issue-comments: highlight text in a Quarto page, comment on it, and have
   the comment filed as a GitHub issue through a Google Apps Script relay. */
(function () {
  "use strict";

  const MAX_QUOTE = 1500;
  const NAME_KEY = "issue-comments:name";

  // Every string readers see. A site can replace any of them with `text:`.
  // A {placeholder} is filled in where it appears.
  const DEFAULT_TEXT = {
    "button": "💬 Comment",
    "page-button": "💬 Comment on this page",
    "heading": "Leave a comment",
    "preview-heading": "Check before posting",
    "section": "Section: {section}",
    "name-label": "Your name",
    "comment-label": "Comment",
    "passcode-label": "Passcode",
    "notice":
      "Comments are posted publicly as GitHub issues on behalf of {owner}, together with " +
      "your name, the highlighted text and a link to this section. You can't edit or delete " +
      "a comment after posting; to change or remove one, {contact}. Your name is saved in " +
      "this browser so you don't have to retype it.",
    "contact-link": "contact {owner}",
    "preview-intro": "This is exactly what will be posted publicly on GitHub on behalf of {owner}:",
    "cancel": "Cancel",
    "edit": "Edit",
    "close": "Close",
    "preview": "Preview",
    "post": "Post publicly",
    "posting": "Posting…",
    "thanks": "Thanks! Posted as {issue}.",
    "issue-link": "issue #{number}",
  };

  function store(key, value) {
    try {
      if (value === undefined) return window.localStorage.getItem(key) || "";
      window.localStorage.setItem(key, value);
    } catch (e) {
      return "";
    }
  }

  function el(tag, attrs, children) {
    const node = document.createElement(tag);
    Object.entries(attrs || {}).forEach(([k, v]) => {
      if (k === "text") node.textContent = v;
      else if (v !== false && v != null) node.setAttribute(k, v === true ? "" : v);
    });
    (children || []).forEach((c) =>
      node.appendChild(typeof c === "string" ? document.createTextNode(c) : c)
    );
    return node;
  }

  // Only allow ordinary links for the contact address.
  function safeLink(url) {
    return /^(https?:|mailto:|\/|\.\/|\.\.\/)/i.test(url || "") ? url : null;
  }

  // Splits a string on its {placeholders} and puts in each value, which may
  // be text or an element. A placeholder with no value stays as written.
  function fill(template, values) {
    return String(template).split(/(\{[a-z-]+\})/).filter(Boolean).map((part) => {
      const key = part.slice(1, -1);
      return part[0] === "{" && Object.prototype.hasOwnProperty.call(values, key) ? values[key] : part;
    });
  }

  // Must match buildIssue_ in apps-script/Code.gs.
  function issueTitle(section, comment) {
    const flat = comment.replace(/\s+/g, " ");
    const words = flat.slice(0, 60) + (flat.length > 60 ? "…" : "");
    return (section ? "[" + section.slice(0, 60) + "] " : "") + words;
  }

  function init() {
    const cfg = window.ISSUE_COMMENTS || {};
    if (!cfg.endpoint) return;

    const owner = cfg.owner || "the site owner";
    const contact = safeLink(cfg.contact);
    const T = Object.assign({}, DEFAULT_TEXT, cfg.text || {});
    const say = (key, values) => fill(T[key], Object.assign({ owner }, values)).join("");

    const root =
      document.querySelector("main#quarto-document-content") ||
      document.querySelector("main") ||
      document.body;

    let current = null; // { quote, section, anchor }

    // ---- Floating "Comment" button shown next to a selection ----
    const selBtn = el("button", {
      type: "button",
      class: "ic-select-btn",
      "aria-label": "Comment on the selected text",
      text: say("button"),
    });
    selBtn.hidden = true;
    selBtn.addEventListener("mousedown", (e) => e.preventDefault()); // keep the selection
    selBtn.addEventListener("click", () => current && openDialog(current));
    document.body.appendChild(selBtn);

    if (cfg.pageButton) {
      const pageBtn = el("button", { type: "button", class: "ic-page-btn", text: say("page-button") });
      pageBtn.addEventListener("click", () =>
        openDialog({ quote: "", section: document.title, anchor: "" })
      );
      document.body.appendChild(pageBtn);
    }

    // ---- Dialog: edit stage ----
    const quoteBox = el("blockquote", { class: "ic-quote" });
    const sectionLine = el("p", { class: "ic-section" });
    const nameInput = el("input", { type: "text", name: "name", required: true, maxlength: "80", autocomplete: "name" });
    const commentInput = el("textarea", { name: "comment", required: true, maxlength: "5000", rows: "6" });
    const passInput = el("input", { type: "password", name: "passcode", autocomplete: "off", required: !!cfg.passcode });
    // Honeypot: hidden from people, often filled in by spam bots.
    const trap = el("input", { type: "text", name: "website", tabindex: "-1", autocomplete: "off", class: "ic-trap", "aria-hidden": "true" });

    const contactText = () =>
      contact
        ? el("a", { href: contact, target: "_blank", rel: "noopener", text: say("contact-link") })
        : document.createTextNode(say("contact-link"));

    const notice = el("p", { class: "ic-note" }, fill(T.notice, { owner, contact: contactText() }));

    const editStage = el("div", {}, [
      sectionLine,
      quoteBox,
      el("label", {}, [say("name-label"), nameInput]),
      el("label", {}, [say("comment-label"), commentInput]),
    ]);
    if (cfg.passcode) editStage.appendChild(el("label", {}, [say("passcode-label"), passInput]));
    editStage.appendChild(trap);
    editStage.appendChild(notice);

    // ---- Dialog: preview stage ----
    const pvTitle = el("p", { class: "ic-pv-title" });
    const pvBody = el("div", { class: "ic-pv-body" });
    const previewStage = el("div", { class: "ic-preview" }, [
      el("p", { class: "ic-section", text: say("preview-intro") }),
      el("div", { class: "ic-pv-card" }, [pvTitle, pvBody]),
    ]);

    const status = el("p", { class: "ic-status", role: "status" });
    const backBtn = el("button", { type: "button" });
    const goBtn = el("button", { type: "submit", class: "ic-primary" });

    const heading = el("h2");
    const form = el("form", { method: "dialog" }, [
      heading, editStage, previewStage, status,
      el("div", { class: "ic-actions" }, [backBtn, goBtn]),
    ]);
    const dialog = el("dialog", { class: "ic-dialog" }, [form]);
    document.body.appendChild(dialog);

    let stage = "edit"; // "edit" | "preview" | "done"

    function setStage(s) {
      stage = s;
      editStage.hidden = s !== "edit";
      previewStage.hidden = s !== "preview";
      goBtn.hidden = s === "done";
      goBtn.disabled = false;
      heading.textContent = say(s === "preview" ? "preview-heading" : "heading");
      backBtn.textContent = say(s === "edit" ? "cancel" : s === "preview" ? "edit" : "close");
      goBtn.textContent = say(s === "edit" && cfg.preview ? "preview" : "post");
      if (s !== "done") { status.textContent = ""; status.className = "ic-status"; }
    }

    backBtn.addEventListener("click", () => {
      if (stage === "preview") setStage("edit");
      else dialog.close();
    });

    function openDialog(ctx) {
      current = ctx;
      selBtn.hidden = true;
      quoteBox.textContent = ctx.quote;
      quoteBox.hidden = !ctx.quote;
      sectionLine.textContent = ctx.section ? say("section", { section: ctx.section }) : "";
      nameInput.value = store(NAME_KEY);
      commentInput.value = "";
      setStage("edit");
      dialog.showModal();
      (nameInput.value ? commentInput : nameInput).focus();
    }

    function fillPreview(name, comment) {
      pvTitle.textContent = issueTitle(current.section, comment);
      pvBody.replaceChildren(
        el("p", {}, [el("strong", { text: "Submitted by: " }), name + ", via the site's comment form"]),
        el("p", {}, [el("strong", { text: "Section: " }), current.section || "Page"]),
        ...(current.quote ? [el("blockquote", { class: "ic-quote", text: current.quote })] : []),
        el("p", { class: "ic-pv-comment", text: comment })
      );
    }

    async function post(name, comment) {
      const payload = {
        name,
        comment,
        quote: current.quote,
        section: current.section,
        anchor: current.anchor,
        page: location.origin + location.pathname,
        passcode: passInput.value,
        website: trap.value,
      };
      goBtn.disabled = true;
      backBtn.disabled = true;
      status.textContent = say("posting");
      status.className = "ic-status";
      try {
        // text/plain avoids a CORS preflight, which Apps Script cannot answer.
        const res = await fetch(cfg.endpoint, {
          method: "POST",
          headers: { "Content-Type": "text/plain;charset=utf-8" },
          body: JSON.stringify(payload),
        });
        const data = await res.json();
        if (!data.ok) throw new Error(data.error || "The comment was not posted.");
        setStage("done");
        status.className = "ic-status ic-ok";
        const issueText = say("issue-link", { number: String(data.number) });
        status.replaceChildren(...fill(T.thanks, {
          issue: data.url
            ? el("a", { href: data.url, target: "_blank", rel: "noopener", text: issueText })
            : issueText,
        }));
        window.getSelection().removeAllRanges();
      } catch (err) {
        status.textContent = err.message || "Something went wrong. Please try again.";
        status.className = "ic-status ic-error";
        goBtn.disabled = false;
      } finally {
        backBtn.disabled = false;
      }
    }

    form.addEventListener("submit", (e) => {
      e.preventDefault();
      if (stage === "edit" && !form.reportValidity()) return;
      const name = nameInput.value.trim().replace(/\s+/g, " ");
      const comment = commentInput.value.trim();
      if (!name || !comment) return;
      store(NAME_KEY, name);
      if (stage === "edit" && cfg.preview) {
        fillPreview(name, comment);
        setStage("preview");
        goBtn.focus();
      } else {
        post(name, comment);
      }
    });

    // ---- Selection tracking ----
    function sectionFor(node) {
      const start = node.nodeType === 1 ? node : node.parentElement;
      const section = start && start.closest("section[id]");
      if (section) {
        const h = section.querySelector(":scope > h1, :scope > h2, :scope > h3, :scope > h4, :scope > h5, :scope > h6");
        return { section: h ? h.textContent.trim() : section.id, anchor: section.id };
      }
      return { section: document.title, anchor: "" };
    }

    function update() {
      if (dialog.open) return;
      const sel = window.getSelection();
      if (!sel || sel.isCollapsed || sel.rangeCount === 0) {
        selBtn.hidden = true;
        return;
      }
      const range = sel.getRangeAt(0);
      const text = sel.toString().replace(/\s+\n/g, "\n").trim();
      if (text.length < 2 || !root.contains(range.commonAncestorContainer)) {
        selBtn.hidden = true;
        return;
      }
      const info = sectionFor(range.startContainer);
      current = {
        quote: text.length > MAX_QUOTE ? text.slice(0, MAX_QUOTE) + "…" : text,
        section: info.section,
        anchor: info.anchor,
      };
      const rects = range.getClientRects();
      const rect = rects.length ? rects[rects.length - 1] : range.getBoundingClientRect();
      const maxLeft = document.documentElement.clientWidth - 140;
      selBtn.style.top = rect.bottom + window.scrollY + 6 + "px";
      selBtn.style.left = Math.max(8, Math.min(rect.right + window.scrollX - 60, maxLeft)) + "px";
      selBtn.hidden = false;
    }

    let timer = null;
    const schedule = () => {
      clearTimeout(timer);
      timer = setTimeout(update, 120);
    };
    document.addEventListener("selectionchange", schedule);
    window.addEventListener("resize", schedule);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
