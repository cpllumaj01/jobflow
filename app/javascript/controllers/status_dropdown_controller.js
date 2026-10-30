import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "toggle", "panel" ]

  escape(event) {
    if (!this.element.open) return

    event.preventDefault()
    event.stopPropagation()
    this.close()
    this.toggleTarget.focus()
  }

  dismiss(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  dismissFocus(event) {
    if (event.relatedTarget && !this.element.contains(event.relatedTarget)) this.close()
  }

  close() {
    this.element.open = false
  }

  position() {
    if (!this.element.open) return

    const rect = this.toggleTarget.getBoundingClientRect()
    const gap = parseFloat(getComputedStyle(this.panelTarget).marginTop)
    const below = window.innerHeight - rect.bottom - gap
    const above = rect.top - gap
    // On phones the panel stays in the header's flow so it cannot cover its other actions.
    const floating = getComputedStyle(this.panelTarget).position === "absolute"
    const upward = floating && this.panelTarget.scrollHeight > below && above > below
    this.panelTarget.style.top = floating && !upward ? "100%" : "auto"
    this.panelTarget.style.bottom = upward ? "100%" : "auto"
    this.panelTarget.style.maxHeight = `${Math.max(0, upward ? above : below)}px`
  }
}
