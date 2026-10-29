import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "errors"]
  static values = { maxSize: Number, extensions: Array }

  validate() {
    const errors = []
    for (const file of this.inputTarget.files) {
      if (file.size > this.maxSizeValue) {
        errors.push(`${file.name}: must be ${this.maxSizeValue / (1024 * 1024)} MB or smaller per file.`)
      }
      if (file.size === 0) {
        errors.push(`${file.name}: is empty; choose a file with content.`)
      }
      const extension = file.name.includes(".") ? file.name.split(".").pop().toLowerCase() : ""
      if (!this.extensionsValue.includes(extension)) {
        errors.push(`${file.name}: unsupported format. Choose a supported file type listed above.`)
      }
    }

    this.errorsTarget.replaceChildren(...errors.map(message => {
      const item = document.createElement("li")
      item.textContent = message
      return item
    }))
    this.inputTarget.setCustomValidity(errors.join("\n"))
    this.inputTarget.setAttribute("aria-invalid", String(errors.length > 0))
    return errors.length === 0
  }

  submit(event) {
    if (!this.validate()) {
      event.preventDefault()
      this.inputTarget.reportValidity()
    }
  }
}
