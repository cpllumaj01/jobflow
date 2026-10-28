import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["code", "status"]

  async copy() {
    try {
      await navigator.clipboard.writeText(this.codes)
      this.statusTarget.textContent = "Recovery codes copied. Store them somewhere safe."
    } catch {
      this.statusTarget.textContent = "Couldn't copy the codes. Select and copy them manually, or use Download."
    }
  }

  download() {
    const file = new Blob([`JobFlow recovery codes\n\n${this.codes}\n`], { type: "text/plain" })
    const url = URL.createObjectURL(file)
    const link = document.createElement("a")
    link.href = url
    link.download = "jobflow-recovery-codes.txt"
    link.click()
    URL.revokeObjectURL(url)
    this.statusTarget.textContent = "Recovery codes downloaded. Store the file somewhere safe."
  }

  clear() {
    this.codeTargets.forEach(code => code.textContent = "")
    this.statusTarget.textContent = "These codes are no longer available. Generate replacements in Account → Security."
  }

  get codes() {
    return this.codeTargets.map(code => code.textContent).join("\n")
  }
}
