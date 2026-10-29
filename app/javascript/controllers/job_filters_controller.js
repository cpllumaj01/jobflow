import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "status", "selection", "manualSubmit", "dropdown", "toggle", "panel" ]

  static values = {
    debounceDelay: { type: Number, default: 300 }
  }

  connect() {
    this.manualSubmitTarget.hidden = true
    this.updateSelection()
  }

  changeStatuses() {
    this.updateSelection()
    this.submit()
  }

  updateSelection() {
    const selected = this.statusTargets.filter(status => status.checked)
    let label = "All statuses"
    if (selected.length === 1) label = selected[0].labels[0].textContent.trim()
    if (selected.length > 1) label = `${selected.length} statuses selected`
    this.selectionTarget.textContent = label
  }

  escape(event) {
    if (!this.dropdownTarget.open) return

    event.preventDefault()
    this.dropdownTarget.open = false
    this.toggleTarget.focus()
  }

  dismiss(event) {
    if (!this.dropdownTarget.contains(event.target)) this.dropdownTarget.open = false
  }

  dismissFocus(event) {
    // A blur can arrive before the next control receives focus; outside clicks are handled separately.
    if (event.relatedTarget && !this.dropdownTarget.contains(event.relatedTarget)) this.dropdownTarget.open = false
  }

  positionDropdown() {
    if (!this.dropdownTarget.open) return

    const rect = this.toggleTarget.getBoundingClientRect()
    const gap = parseFloat(getComputedStyle(this.panelTarget).marginTop)
    const below = window.innerHeight - rect.bottom - gap
    const above = rect.top - gap
    const upward = this.panelTarget.scrollHeight > below && above > below
    this.panelTarget.style.top = upward ? "auto" : "100%"
    this.panelTarget.style.bottom = upward ? "100%" : "auto"
    this.panelTarget.style.maxHeight = `min(20rem, ${Math.max(0, upward ? above : below)}px)`
  }

  search() {
    this.cancel()
    this.searchTimeout = setTimeout(() => this.submit(), this.debounceDelayValue)
  }

  submit() {
    this.cancel()
    this.element.requestSubmit()
  }

  cancel() {
    clearTimeout(this.searchTimeout)
  }

  disconnect() {
    this.cancel()
  }
}
