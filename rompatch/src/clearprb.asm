; SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
; CLEAR-PRB: called at NEW/boot (128Bh). Reset the printer buffer
; position sysvar so P-channel writes stay inside 5B00h-5BFFh.
        ORG 0EDFh
        ld hl,5B00h
        ld (5C80h),hl        ; PR-CC
        ret
