import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    debounceDelay: { type: Number, default: 300 }
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
