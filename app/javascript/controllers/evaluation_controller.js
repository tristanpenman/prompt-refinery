import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["status", "submit"]

  start() {
    this.statusTarget.hidden = false
    this.submitTarget.disabled = true
    this.submitTarget.value = "Evaluating…"
  }

  finish() {
    this.statusTarget.hidden = true
    this.submitTarget.disabled = false
    this.submitTarget.value = "Run evaluation"
  }
}
