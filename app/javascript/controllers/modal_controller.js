import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="modal"
export default class extends Controller {
  static targets = ["overlay"]

  connect() {
    // モーダルが表示されたら自動的に呼ばれる
    // モーダル表示時 → スクロール禁止
    document.body.classList.add("overflow-hidden")
  }

  close() {
    this.element.classList.add('opacity-0')

    // スクロール解除
    document.body.classList.remove("overflow-hidden")

    setTimeout(() => {
      this.element.style.display = 'none'
    }, 300)
  }

  closeOnOverlay(event) {
    // オーバーレイをクリックした時だけ閉じる
    if (event.target === this.overlayTarget) {
      this.close()
    }
  }
}
