import { Controller } from "@hotwired/stimulus"

// ラベリング画面。カードを1枚ずつ表示し、キーで移動と評価を行う。
// Stimulus は HTML 側の data-controller / data-action / data-*-target を見て、この class のインスタンスを要素ごとに作る。
//
// 流れ: U/D で評価を送信 → Turbo が評価欄を差し替える → その理由入力欄にフォーカス
//       → Enter で理由を送信して次のカードへ(空でも可)、Esc でフォーカスを外す(その後 J で次へ)
export default class extends Controller {
  static targets = [ "card", "position", "done", "reason" ]

  connect() {
    this.index = 0
    this.focusReason = false
    this.show()
  }

  // Stimulus は target の要素が DOM に加わるたびに <名前>TargetConnected を呼ぶ(MutationObserver で監視している)。
  // Turbo が評価欄を差し替えると新しい理由入力欄がここへ届くので、評価を送った直後だけフォーカスを移す。
  // (画面を開いた時にも全入力欄分が呼ばれるため、focusReason の旗で区別する)
  reasonTargetConnected(input) {
    if (this.draft?.card.contains(input)) { // 評価の送信前に打っていた未送信の理由を、差し替え後の入力欄へ戻す
      input.value = this.draft.value
      this.draft = null
    }
    if (this.focusReason && this.cardTargets[this.index]?.contains(input)) {
      this.focusReason = false
      input.focus()
    }
  }

  // data-action の keydown@window から呼ばれる
  key(event) {
    if (event.isComposing || event.metaKey || event.ctrlKey || event.altKey) return // IME 変換中と修飾キーつきは無視
    if (event.target.closest("input, textarea")) return // 一言理由の入力中は無視する

    switch (event.key.toLowerCase()) {
      case "j": this.move(1); break
      case "k": this.move(-1); break
      case "u": this.rate(1); break
      case "d": this.rate(-1); break
    }
  }

  // 現在のカードの 👍/👎 ボタンのフォームを送る。応答は Turbo Stream で評価欄だけが差し替わる
  rate(rating) {
    const button = this.cardTargets[this.index]?.querySelector(`button[data-rating="${rating}"]`)
    if (!button) return
    this.focusReason = true
    button.form.requestSubmit()
  }

  // 理由入力欄の keydown.esc から呼ばれる
  blur(event) {
    event.target.blur()
  }

  // 前へ/次へボタン。J/K と同じで何も保存しない
  previous() { this.move(-1) }
  next() { this.move(1) }

  // フォームの送信が始まったとき。理由のフォーム(Enter か送信ボタン)なら、入力欄のフォーカスを外して
  // (ソフトウェアキーボードを閉じる)そのまま次のカードへ進む。評価のフォームでは進まない
  submitted(event) {
    if (event.target.classList.contains("rate")) { // 評価欄は応答で差し替わるので、未送信の理由を控えておく
      const card = event.target.closest("[data-labeling-target=card]")
      const input = card?.querySelector("input[name=reason]")
      this.draft = input && input.value !== input.defaultValue ? { card, value: input.value } : null // 空に消した編集も含む
    }
    if (!event.target.classList.contains("reason")) return
    this.draft = null // 評価の応答が失敗して残った控えや旗は、理由の送信で捨てる
    this.focusReason = false
    document.activeElement?.blur()
    this.move(1)
  }

  // index が cardTargets.length のときは「すべて終わり」の表示
  move(delta) {
    this.index = Math.min(Math.max(this.index + delta, 0), this.cardTargets.length)
    this.show()
  }

  show() {
    this.cardTargets.forEach((card, i) => { card.hidden = i !== this.index })
    this.doneTarget.hidden = this.index < this.cardTargets.length
    this.positionTarget.textContent = this.doneTarget.hidden ? `${this.index + 1} / ${this.cardTargets.length}` : "完了"
    window.scrollTo(0, 0)
  }
}
