; SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
; CLOSE# command entry: report O.
        ORG 16E5h
        rst 8
        DEFB 17h             ; report O, Bad stream
