#!/bin/bash
set -e
################################################################################
#                           User Definable Variables                           #
#------------------------------------------------------------------------------#
# Change these to your liking, or have them passed into this script through    #
# environment variables. These variables are pretty safe to tweak.             #
################################################################################

EMAIL_ADDRESS=${EMAIL_ADDRESS:-""}
EMAIL_SUBJECT_PREFIX=${EMAIL_SUBJECT_PREFIX:-"SnapRAID on $(hostname) - "}

DELETE_THRESHOLD=${DELETE_THRESHOLD:-"0"}
UPDATE_THRESHOLD=${UPDATE_THRESHOLD:-"-1"}  # -1 for disabled

RUN_SCRUB=${RUN_SCRUB:-"false"}
SCRUB_PERCENT=${SCRUB_PERCENT:-"8"}
SCRUB_AGE=${SCRUB_AGE:-"10"}

################################################################################
#                      Additional Configurable Variables                       #
#------------------------------------------------------------------------------#
# Do not change these unless you know what you are doing.                      #
################################################################################

FORCE_SYNC=${FORCE_SYNC:-"false"}
NONINTERACTIVE=${NONINTERACTIVE:-"false"}

LOG_FILE=${LOG_FILE:-""}
MAIL_ATTACH_LOG=${MAIL_ATTACH_LOG:-"false"}
CONFIG_FILE=${CONFIG_FILE:-"/etc/snapraid.conf"}

SNAPRAID_BIN=${SNAPRAID_BIN:-"/usr/local/bin/snapraid"}
MAIL_BIN=${MAIL_BIN:-"/usr/bin/mutt"}

################################################################################
#                        The "main" part of this script                        #
################################################################################

# Source all the other files containing the actual functions we are using.
. "$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"/utils_main.sh
. "$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"/utils_snapraid.sh
. "$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"/utils_mail.sh

# The "main" function.
main() {
    if [ -n "${LOG_FILE}" ]; then
        LOG_FILE=$(mktemp)
        info "Starting SnapRAID Job"
        warning "No logfile given, logging to temporary file ${LOG_FILE}"
    else
        info "Starting SnapRAID Job"
    fi

    # Check any input arguments that may or may not have been supplied.
    check_input_arguments "$@"

    # Make sure we have the necessary files and variables.
    check_integrity

    # Touch all files with zero sub-second timestamp.
    sub_zero_touch

    # Check if there are any changes to the content of the array.
    check_diff

    # Determine if a 'sync' should be run.
    if should_sync; then
        info "Running 'sync' job"
        echo "$(date +%Y-%m-%dT%H:%M:%S%z) - Starting sync job" >> ${mail_body}
        echo "" >> ${mail_body}

        # Add the 'diff' output to the mail.
        cat ${tmp_file} | tail -n 8 | head -n 7 >> ${mail_body}
        echo "" >> ${mail_body}

        # Run the sync.
        run_snapraid sync log

        info "Sync job finished"
        echo "$(date +%Y-%m-%dT%H:%M:%S%z) - Sync job finished" >> ${mail_body}
        echo "" >> ${mail_body}
        check_snapraid_status "sync"
    fi

    # Determine if a 'scrub' should be run.
    if should_scrub; then
        info "Running 'scrub' job - this might take a very long time"
        echo "$(date +%Y-%m-%dT%H:%M:%S%z) - Starting scrub job" >> ${mail_body}

        run_snapraid "scrub -p ${SCRUB_PERCENT} -o ${SCRUB_AGE}" log

        info "Scrub job finished"
        echo "$(date +%Y-%m-%dT%H:%M:%S%z) - Scrub job finished" >> ${mail_body}
        echo "" >> ${mail_body}

        check_snapraid_status "scrub"
    fi

    info "SnapRAID Job Completed"
}

main "$@"
exit 0
