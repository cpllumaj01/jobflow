import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggle", "panel", "firstLink"]

  connect() {
    if (!this.hasToggleTarget) return

    this.close()
    this.toggleTarget.hidden = false
  }

  toggle() {
    const expanded = this.toggleTarget.getAttribute("aria-expanded") === "true"
    this.toggleTarget.setAttribute("aria-expanded", String(!expanded))
    this.panelTarget.classList.toggle("hidden", expanded)
  }

  close() {
    if (!this.hasToggleTarget) return

    this.toggleTarget.setAttribute("aria-expanded", "false")
    this.panelTarget.classList.add("hidden")
  }

  escape(event) {
    if (!this.hasToggleTarget || this.toggleTarget.getAttribute("aria-expanded") !== "true") return

    event.preventDefault()
    this.close()
    this.toggleTarget.focus()
  }

  dismiss(event) {
    if (this.element.contains(event.relatedTarget)) return

    // A breakpoint can hide the focused control before the resize event fires.
    if (!event.target.getClientRects().length) {
      this.resize(event)
    } else {
      this.close()
    }
  }

  resize(event) {
    if (!this.hasToggleTarget) return

    const focused = event?.type === "focusout" ? event.target : document.activeElement
    const desktop = getComputedStyle(this.toggleTarget).display === "none"
    this.close()
    if (desktop && focused === this.toggleTarget) {
      this.firstLinkTarget.focus()
    } else if (!desktop && this.panelTarget.contains(focused)) {
      this.toggleTarget.focus()
    }
  }
}
