import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "theme"

export default class extends Controller {
  toggle() {
    const theme = document.documentElement.dataset.theme === "dark" ? "light" : "dark"
    document.documentElement.dataset.theme = theme
    try { localStorage.setItem(STORAGE_KEY, theme) } catch {}
    this.element.setAttribute("aria-pressed", theme === "dark")
  }

  connect() {
    this.element.setAttribute("aria-pressed", document.documentElement.dataset.theme === "dark")
  }
}
