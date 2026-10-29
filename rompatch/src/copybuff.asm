; SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
; COPY-BUFF: called from the kept output driver and main loop to flush
; the printer buffer. Discard the buffer and reset PR-CC (fall into
; the CLEAR-PRB stub): LPRINT becomes a safe no-op.
        ORG 0ECDh
        jp 0EDFh
