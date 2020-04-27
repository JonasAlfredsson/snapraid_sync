#!/bin/bash
################################################################################
#                          SnapRAID Related Functions                          #
#------------------------------------------------------------------------------#
# This file contains functions which are in some way interacting with the      #
# SnapRAID binary. These are all invoked from the "main" function.             #
################################################################################

# Find all parity files and check if they exist. Exit if there are no valid
# parity files present.
parse_parity_files() {
    cat ${CONFIG_FILE} | sed -r -n 's/^[2-6]?-?parity (.*)$/\1/p'
}
check_parity_files() {
    nbr_parity_files=0
    local valid_parity_files=0
    while read parity_file; do
        nbr_parity_files=$((nbr_parity_files+1))
        if [ -f "${parity_file}" ]; then
            valid_parity_files=$((valid_parity_files+1))
        else
            warning "Could not find parity file '${parity_file}'"
        fi
    done <<<$(parse_parity_files)
    if [ "${valid_parity_files}" -eq 0 ]; then
        local str="Could not find any parity files"
        error "${str}"
        if [ "${FORCE_SYNC,,}" == "true" ]; then
            warning "The 'force' argument is true; overriding this error"
        else
            echo "${str}." >> ${mail_body}
            send_mail "ERROR"
            exit 1
        fi
    fi
}

# Find all content files and check if they exist. Exit if there are no valid
# content files present.
parse_content_files() {
    cat ${CONFIG_FILE} | sed -r -n 's/^content (.*)$/\1/p'
}
check_content_files() {
    nbr_content_files=0
    local valid_content_files=0
    while read content_file
    do
        nbr_content_files=$((nbr_content_files+1))
        if [ -f "${content_file}" ]; then
            valid_content_files=$((valid_content_files+1))
        else
            warning "Could not find content file '${content_file}'"
        fi
    done <<<$(parse_content_files)
    if [ "${valid_content_files}" -eq 0 ]; then
        local str="Could not find any content files"
        error "${str}"
        if [ "${FORCE_SYNC,,}" == "true" ]; then
            warning "The 'force' argument is true; overriding this error"
        else
            echo "${str}." >> ${mail_body}
            send_mail "ERROR"
            exit 1
        fi
    fi
    if [ "${nbr_content_files}" -lt "${nbr_parity_files}" ]; then
        warning "SnapRAID demands at least 'nbr of parity files + 1' content files"
    fi
}

# Check that the "threshold" environment variables are set, are integers and
# are within their respective valid range.
check_threshold_values() {
    local str="OK"
    if [ -z "${2}" ]; then
        str="The variable '${1}' is not defined"
    elif ! [[ "${2}" =~ ^-?[0-9]+$ ]]; then
        str="The variable '${1}' is set to '${2}' which is not recognized as an integer"
    elif [ ! "${2}" -ge "${3}" ]; then
        str="The variable '${1}' (${2}) needs to be equal or greater than ${3}"
    fi

    if [ "${str}" != "OK" ]; then
        error "${str}"
        echo "${str}." >> ${mail_body}
        send_mail "ERROR"
        exit 1
    fi
}

# Verify that all critical files and variables exist and are valid.
check_integrity() {
    # Test that DELETE_THRESHOLD exist, is an integer and is equal or greater
    # than 0.
    check_threshold_values "DELETE_THRESHOLD" "${DELETE_THRESHOLD}" "0"

    # Test that UPDATE_THRESHOLD exist, is an integer and is equal or greater
    # than -1.
    check_threshold_values "UPDATE_THRESHOLD" "${UPDATE_THRESHOLD}" "-1"

    # Test if the config file exists, and then move on to test the parity and
    # content files as well.
    if [ -f "${CONFIG_FILE}" ]; then
        check_parity_files
        check_content_files
    else
        error "Could not find the config file '${CONFIG_FILE}'"
        echo "Could not find the config file." >> ${mail_body}
        send_mail "ERROR"
        exit 1
    fi
}

# If there are any files with a zero sub-second timestamp we will go around and
# 'touch' those files to make it not so. This will help SnapRAID in the future
# when it is trying to determine if a file has changed or not.
sub_zero_touch(){
    info "Checking for files with zero sub-second timestamp"
    local sub_zero_files=$(run_snapraid status | sed -r -n 's/^You have ([0-9]+) files? with zero sub-second timestamp.$/\1/p')
    if [ -n "${sub_zero_files}" ]; then
        info "Found ${sub_zero_files} files with zero sub-second timestamp"
        info "Running SnapRAID 'touch' command"
        run_snapraid touch log
        info "SnapRAID 'touch' finished"
    else
        info "No files with zero sub-second timestamp found"
    fi
}

# Run a 'diff' job to see if anything have changed on the array.
check_diff() {
    info "Running SnapRAID 'diff' command"
    run_snapraid diff tmp_file
    cat "${tmp_file}" >> ${LOG_FILE}
    info "SnapRAID 'diff' finished"

    # Try to extract all the values.
    ADD_COUNT=$(cat ${tmp_file} | sed -r -n 's/^\s*([0-9]+) added$/\1/p')
    DEL_COUNT=$(cat ${tmp_file} | sed -r -n 's/^\s*([0-9]+) removed$/\1/p')
    UPDATE_COUNT=$(cat ${tmp_file} | sed -r -n 's/^\s*([0-9]+) updated$/\1/p')
    MOVE_COUNT=$(cat ${tmp_file} | sed -r -n 's/^\s*([0-9]+) moved$/\1/p')
    COPY_COUNT=$(cat ${tmp_file} | sed -r -n 's/^\s*([0-9]+) copied$/\1/p')

    # Sanity check to make sure that we were able to get all expected values
    # from the output of the 'diff' job.
    if [ -z "${ADD_COUNT}" -o -z "${DEL_COUNT}" -o -z "${UPDATE_COUNT}" -o -z "${MOVE_COUNT}" -o -z "${COPY_COUNT}" ]; then
        # We could not read one or more of the expected values, something is
        # wrong. Print an error, and attach the 'diff' command's output to the
        # main log file.
        local str="Failed to extract one or more count values from 'diff' job"
        error "${str}"
        error "A=${ADD_COUNT}, D=${DEL_COUNT}, U=${UPDATE_COUNT}, M=${MOVE_COUNT}, C=${COPY_COUNT}"
        cat ${tmp_file} >> ${LOG_FILE}

        # Assemble an email with these details.
        echo "${str}." >> ${mail_body}
        echo "" >> ${mail_body}
        email_add_short_log ${tmp_file}
        send_mail "ERROR"
        exit 1
    fi

    # The 'diff' command went well, and we have managed to extract the
    # interesting values into separate variables.
    info "Summary of changes: A=${ADD_COUNT}, D=${DEL_COUNT}, U=${UPDATE_COUNT}, M=${MOVE_COUNT}, C=${COPY_COUNT}"
}

# Function to check if all requirements for a 'sync' are fulfilled.
# Will return "0" (i.e. "true") if a 'sync' should be performed.
should_sync() {
    local sync=1
    if [ "${ADD_COUNT}" -gt 0 -o "${DEL_COUNT}" -gt 0 -o "${UPDATE_COUNT}" -gt 0 -o "${MOVE_COUNT}" -gt 0 -o "${COPY_COUNT}" -gt 0 ]; then
        # There are differences, prepare to preform a sync.
        sync=0
        if [ "${DEL_COUNT}" -gt "${DELETE_THRESHOLD}" ]; then
            warning "Delete count (${DEL_COUNT}) exceeds the defined threshold (${DELETE_THRESHOLD})"
            sync=1
        fi
        if [ "${UPDATE_THRESHOLD}" -ne "-1" -a "${UPDATE_COUNT}" -gt "${UPDATE_THRESHOLD}" ]; then
            warning "Update count (${UPDATE_COUNT}) exceeds the defined threshold (${UPDATE_THRESHOLD})"
            sync=1
        fi

        # If we have exceeded any threshold value we can override them here.
        if [ "${sync}" -ne 0 ] && [ "${FORCE_SYNC,,}" == "true" ]; then
            if [ "${NONINTERACTIVE}" == "true" ]; then
                warning "The 'force' argument is true; overriding any threshold warnings"
                sync=0
            else
                # Unless state otherwise by the NONINTERACTIVE environment
                # variable, we will wait for user confirmation before forcing
                # a sync.
                info "The 'NONINTERACTIVE' variable is not true, asking user what to do..."
                read -p "Would you still like to sync? [y/N]" -n 1 -r
                echo
                if [[ "${REPLY}" =~ ^[Yy]$ ]]; then
                    sync=0
                fi
            fi
        fi
        if [ "${sync}" -ne 0 ]; then
            # Threshold exceeded and "force sync" is not true, so exit.
            info "Threshold values have been exceeded; aborting"
            email_no_sync
            exit 1
        fi
    else
        info "No changes detected; not running 'sync' job"
    fi
    return ${sync}
}

# Function to check if all requirements for a 'scrub' are fulfilled.
# Will return "0" (i.e. "true") if a 'scrub' should be performed.
should_scrub() {
    if [ "${RUN_SCRUB,,}" == "true" ]; then
        if [ "${SCRUB_PERCENT}" -gt 0 ]; then
            return 0
        else
            local str="A 'scrub' is requested, but scrub percentage is set to ${SCRUB_PERCENT}; will not scrub"
            warning "${str}"
            echo "${str}." >> ${mail_body}
            send_mail "WARNING"
        fi
    fi
    return 1
}

# After a 'sync' or a 'scrub' has completed, take a look at the log output to
# see if it is missing some of the indicators which signify that everything
# wen well.
check_snapraid_status() {
    # Get extra information from the status command.
    run_snapraid status tmp_file
    local no_error=$(cat ${tmp_file} | tail -n 6 | grep -oP 'No error detected.' || (echo "false"))

    # See if "Everything OK" is present in the log output.
    local is_ok=$(cat ${LOG_FILE} | tail -n $(( ${nbr_content_files} * 2 + 8 )) | grep -oP 'Everything OK' || (echo "false"))
    if [ "${is_ok}" != "Everything OK" ]; then
        # If the "OK" message does not show there is a chance that there was
        # just "Nothing to do".
        local nothing_to_do=$(cat ${LOG_FILE} | tail -n 8 | grep -oP 'Nothing to do' || (echo "false"))
        if [ "${nothing_to_do}" == "Nothing to do" ]; then
            echo "SnapRAID reported 'Nothing to do'" >> ${mail_body}
            echo "" >> ${mail_body}
        else
            warning "Could not find the string 'Everything OK' at the end of the log; aborting since something might be wrong"
            email_no_ok "Could not find the string 'Everything OK' at the end of the log."
            exit 1
        fi
    fi

    # It might also be so that the 'status' command reports errors.
    if [ "${no_error}" != "No error detected." ]; then
        warning "SnapRAID 'status' command reports errors; aborting"
        email_no_ok "SnapRAID 'status' command reports errors."
        exit 1
    fi

    # Send a mail stating that everything went fine.
    email_ok
}

# A switch case for easier management of running SnapRAID, and controlling where
# its output goes.
run_snapraid() {
    echo ""
    case "${2}" in
        "")
            ${SNAPRAID_BIN} -c ${CONFIG_FILE} ${1}
            wait
            ;;
        "tmp_file")
            echo -n "" > ${tmp_file}
            ${SNAPRAID_BIN} -c ${CONFIG_FILE} ${1} 2>&1 | tee -a ${tmp_file}
            wait
            ;;
        "log")
            ${SNAPRAID_BIN} -c ${CONFIG_FILE} ${1} 2>&1 | tee -a ${LOG_FILE}
            wait
            ;;
        *)
            error "Unknown option '${2}'"
            exit 1
            ;;
    esac
    echo ""
}
