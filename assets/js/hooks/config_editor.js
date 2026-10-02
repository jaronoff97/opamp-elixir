// A CodeMirror YAML editor for a hidden <textarea>. The editor writes its text back into the
// textarea before the form submits, so the LiveView receives it as a normal form field.
import {EditorView, basicSetup} from "codemirror"
import {EditorState} from "@codemirror/state"
import {StreamLanguage} from "@codemirror/language"
import {yaml} from "@codemirror/legacy-modes/mode/yaml"

export const ConfigEditor = {
  mounted() {
    this.view = new EditorView({
      state: EditorState.create({doc: this.el.value, extensions: [basicSetup, StreamLanguage.define(yaml)]}),
      parent: document.getElementById(this.el.dataset.editor),
    })
    this.el.form.addEventListener("submit", () => { this.el.value = this.view.state.doc.toString() })
  },
  destroyed() {
    this.view?.destroy()
  },
}
