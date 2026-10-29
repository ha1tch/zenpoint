; SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
; S-SCRN$-S (SCREEN$ reverse lookup, dropped): report C. The scanner
; calls here (266Bh) when SCREEN$ is evaluated.
        ORG 2535h
        rst 8
        DEFB 0Bh             ; report C, Bad BASIC
