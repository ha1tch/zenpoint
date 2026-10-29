; SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
; T-19: repoint the DRAW command table entry from 2382h (now CIRCLE
; code) to the replacement entry at 2410h (draw.asm).
        ORG 1AD4h
        DEFW 2410h
