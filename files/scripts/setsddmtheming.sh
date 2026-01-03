#!/usr/bin/env bash

set -oue pipefail

# The sequoia_2 theme includes all necessary styling
# Verify the theme configuration is correct
if [ -f /etc/sddm.conf.d/theme.conf ]; then
    # Ensure theme is set via override file
    sed -i 's/Current=.*/Current=sequoia_2/' /etc/sddm.conf.d/theme.conf
fi

# Additional: Verify theme directory exists
[ -d /usr/share/sddm/themes/sequoia_2 ] || {
    echo "Error: sequoia_2 theme not found!"
    exit 1
}

echo "SDDM theme configured successfully"
