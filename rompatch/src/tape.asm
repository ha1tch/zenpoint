; SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
; SAVE/LOAD/VERIFY/MERGE command entry (SAVE-ETC): report J.
        ORG 0605h
        rst 8
        DEFB 12h             ; report J, Bad I/O device
