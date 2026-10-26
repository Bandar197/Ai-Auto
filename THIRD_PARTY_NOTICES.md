# Third-party notices

## dtc-database (manufacturer-specific DTC descriptions)

`shared/kb/dtc_oem.json` contains manufacturer-specific code descriptions imported from
<https://github.com/Wal33D/dtc-database> (`data/source-data/*_codes.txt`) with
`tools/import_oem_dtcs.py`. The data is community-compiled and **not verified** against
manufacturer service information; the app labels it as such. Known-bad input
(`infiniti_codes.txt`, byte-identical to the Honda file) and the make-less
`other_codes.txt` were not imported. Generic codes were not imported (the bundled generic
knowledge base is maintained separately).

```
MIT License

Copyright (c) 2024 Wal33D (Waleed Judah)

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

## AndrOBD

Not used. AndrOBD is GPL-3.0; no code or data was copied from it (copying would
require releasing this app under the GPL).

## pdf / bidi (Dart packages, on-device PDF reports)

`pdf` (Apache-2.0, DavBfr) and `bidi` (MIT, Mahdi K. Fard) are used unmodified as pub
dependencies to build the Arabic/English PDF report on the device.
