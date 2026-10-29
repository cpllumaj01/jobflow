import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "toggle", "showIcon", "hideIcon"]
  static values = { label: String }

  connect() {
    this.hide()
    this.toggleTarget.hidden = false
  }

  keepInputFocus(event) {
    if (document.activeElement === this.inputTarget) event.preventDefault()
  }

  toggle() {
    const { selectionStart, selectionEnd, selectionDirection } = this.inputTarget
    this.inputTarget.type = this.inputTarget.type === "password" ? "text" : "password"
    this.inputTarget.setSelectionRange(selectionStart, selectionEnd, selectionDirection)
    this.update()
  }

  hide() {
    this.inputTarget.type = "password"
    this.update()
  }

  update() {
    const visible = this.inputTarget.type === "text"
    this.toggleTarget.setAttribute("aria-label", `${visible ? "Hide" : "Show"} ${this.labelValue}`)
    this.showIconTarget.hidden = visible
    this.hideIconTarget.hidden = !visible
  }
}
