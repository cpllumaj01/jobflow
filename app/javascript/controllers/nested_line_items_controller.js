import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["items", "template", "row", "destroy"]

  nextIndex = Date.now()

  add() {
    const index = this.nextIndex++
    const html = this.templateTarget.innerHTML.replaceAll("NEW_LINE_ITEM", index)
    this.itemsTarget.insertAdjacentHTML("beforeend", html)
  }

  remove(event) {
    const row = this.rowTargets.find((row) => row.contains(event.currentTarget))

    if (row.dataset.persisted === "true") {
      this.destroyTargets.find((field) => row.contains(field)).value = "1"
      row.hidden = true
    } else {
      row.remove()
    }
  }
}
