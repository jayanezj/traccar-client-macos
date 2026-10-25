#!/bin/bash
# Shared by build/test/verification scripts; development never falls back to ad hoc.
signing_mode="${TRACCAR_SIGNING_MODE:-development}"
case "$signing_mode" in
    development)
        signing_options=("CODE_SIGN_STYLE=Manual")
        ;;
    adhoc)
        signing_options=("CODE_SIGN_STYLE=Manual" "CODE_SIGN_IDENTITY=-" "DEVELOPMENT_TEAM=")
        ;;
    *)
        echo "TRACCAR_SIGNING_MODE must be development or adhoc." >&2
        exit 2
        ;;
esac
