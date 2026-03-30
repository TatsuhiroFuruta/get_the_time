import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="hamburger"
export default class extends Controller {
  static targets = ["menu", "button", "overlay"]

  toggle() {
    // メニューの表示/非表示を切り替え
    // クラスがあれば削除、なければ追加
    this.menuTarget.classList.toggle("-translate-x-full")

    this.buttonTarget.classList.toggle("active")
    this.overlayTarget.classList.toggle("hidden")
  }

  close() {
    this.menuTarget.classList.add("-translate-x-full")
    this.buttonTarget.classList.remove("active")
    this.overlayTarget.classList.add("hidden")
  }
}

