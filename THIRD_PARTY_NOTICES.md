# Third-party notices

## TouchBar Flicker Fix / touchbar-off

The panel power-off approach in `Sources/Panel.swift` follows
[TouchBar Flicker Fix](https://github.com/sennamint/touchbar-flicker-fix), which builds on
Guillermo Pages' [touchbar-off](https://github.com/gbili/touchbar-off). That covers using
`DFRBrightnessClient` `turnOffWithPeriod:`/`turnOnWithPeriod:` with a zero period, reading
`DFRGetStatus`, and listening with `DFRRegisterStatusChangeCallback`. Their licence:

```
MIT License

Copyright (c) 2026 Guillermo Pages
Copyright (c) 2026 TouchBar Flicker Fix contributors

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
```

## System-modal Touch Bar API

The full-width black backup bar uses AppKit's private
`+[NSTouchBar presentSystemModalTouchBar:placement:systemTrayItemIdentifier:]`. Touch Bar
customisers such as Pock, MTMR and XTouchBar documented and use it. No code from those
projects is included.
