# Third-party notices

## SuperDictate / Parakey

Parts of VoiceInput's hotkey model, event-tap behavior, hotkey recording
behavior, floating panel configuration, and recording/processing HUD drawing
were adapted from SuperDictate at commit
`4166fbdd6e7ea86a62d04d1085c4dfe819095b97`:

https://github.com/shlgd/SuperDictate

The referenced implementation is primarily in
`swift/Sources/Parakey/main.swift`. VoiceInput does not include SuperDictate's
speech recognition, audio recording, models, cleanup, updater, history,
background service, or import features.

MIT License

Copyright (c) 2026 Richard Courtman

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## FluidAudio

VoiceInput links FluidAudio 0.15.5 through Swift Package Manager. No FluidAudio
source is copied into this repository.

Copyright (c) FluidInference contributors. Licensed under the Apache License,
Version 2.0. The license text and dependency notices are available in the
upstream distribution:

https://github.com/FluidInference/FluidAudio/tree/v0.15.5

https://www.apache.org/licenses/LICENSE-2.0

## NVIDIA Parakeet TDT 0.6B v3 / FluidAudio CoreML conversion

The model is not bundled with VoiceInput. FluidAudio downloads the CoreML
conversion from `FluidInference/parakeet-tdt-0.6b-v3-coreml` on first use.
The upstream NVIDIA Parakeet TDT 0.6B v3 model is distributed under CC BY 4.0.
Attribution and details are preserved in `MODEL_ATTRIBUTION.md`.
