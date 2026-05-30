#!/bin/sh
# Pre-installation hook. Kept minimal; honors the WD debug flag.
[ -f /tmp/debug_apkg ] && echo "APKG_DEBUG: $0 $*" >> /tmp/debug_apkg

# DO NOT REMOVE
exit 0
