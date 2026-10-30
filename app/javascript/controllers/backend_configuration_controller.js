import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["adapter", "name", "ollama", "bedrock"]

  connect() {
    this.update()
  }

  update() {
    if (!this.hasAdapterTarget) return

    const bedrock = this.adapterTarget.value === "bedrock"
    this.nameTarget.placeholder = bedrock ? "Amazon Bedrock" : "RK3588 board"
    this.toggle(this.ollamaTarget, !bedrock)
    this.toggle(this.bedrockTarget, bedrock)
  }

  toggle(section, visible) {
    section.hidden = !visible
    section.querySelectorAll("input").forEach((input) => {
      input.disabled = !visible
      input.required = visible
    })
  }
}
