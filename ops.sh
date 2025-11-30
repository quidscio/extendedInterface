#!/usr/bin/env bash

# Overrides for ubiquitous_bash.sh to add verbose, dynamic certificate link management.
_install_certs() {
    _messageNormal 'install: certs **RMH**'
    if [[ $(id -u 2> /dev/null) == "0" ]] || [[ "$USER" == "root" ]] || _if_cygwin
    then
        sudo() {
            [[ "$1" == "-n" ]] && shift
            "$@"
        }
    fi

    _install_certs_cp_procedure() {
        _messagePlain_nominal '_install_certs: install: '"$2"
        [[ -e "$2" ]] && sudo -n cp -f "$1"/*.crt "$2"
    }
    _install_certs_cp() {
        [[ -e /cygdrive/c/core ]] && mkdir -p /cygdrive/c/core/data/certs/
        _install_certs_cp_procedure "$1" /cygdrive/c/core/data/certs/

        mkdir -p "$HOME"/core/data/certs/
        _install_certs_cp_procedure "$1" "$HOME"/core/data/certs/

        _install_certs_cp_procedure "$1" /usr/local/share/ca-certificates/

        _if_cygwin && _install_certs_cp_procedure "$1" /etc/pki/ca-trust/source/anchors/

        return 0
    }
    _install_certs_write() {
        if [[ -e "$scriptAbsoluteFolder"/_lib/kit/app/researchEngine/kit/certs ]]
        then
            _install_certs_cp "$scriptAbsoluteFolder"/_lib/kit/app/researchEngine/kit/certs
            return
        fi
        if [[ -e "$scriptAbsoluteFolder"/_lib/ubiquitous_bash/_lib/kit/app/researchEngine/kit/certs ]]
        then
            _install_certs_cp "$scriptAbsoluteFolder"/_lib/ubiquitous_bash/_lib/kit/app/researchEngine/kit/certs
            return
        fi
        if [[ -e "$scriptAbsoluteFolder"/_lib/ubDistBuild/_lib/ubiquitous_bash/_lib/kit/app/researchEngine/kit/certs ]]
        then
            _install_certs_cp "$scriptAbsoluteFolder"/_lib/ubDistBuild/_lib/ubiquitous_bash/_lib/kit/app/researchEngine/kit/certs
            return
        fi
        return 1
    }

    local cert_link_dir="/etc/pki/tls/certs"
    local anchors_dir="/etc/pki/ca-trust/source/anchors"
    local removed_hash_manifest=""
    local cert_log_dir="/cygdrive/c/core/logs"
    local cert_log_file=""
    local cert_log_enabled="false"

    _install_certs_log() {
        [[ "$cert_log_enabled" == "true" ]] || return 0
        local timestamp
        timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2> /dev/null)
        [[ "$timestamp" == "" ]] && timestamp=$(date)
        echo "[$timestamp] $*" >> "$cert_log_file"
    }

    _install_certs_init_logging() {
        _if_cygwin || return 0
        mkdir -p "$cert_log_dir" > /dev/null 2>&1
        cert_log_file="$cert_log_dir"/ubiquitous_certs.log
        cert_log_enabled="true"
        _install_certs_log "=== _install_certs start: $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null) ==="
    }

    _install_certs_log_identity() {
        _if_cygwin || return 0
        local cyg_root
        local bash_path
        local bash_win
        cyg_root=$(cygpath -m / 2> /dev/null)
        bash_path=$(type -p bash 2> /dev/null)
        [[ -n "$bash_path" ]] && bash_win=$(cygpath -m "$bash_path" 2> /dev/null)
        local saf_win scriptlocal_win
        [[ -n "$scriptAbsoluteFolder" ]] && saf_win=$(cygpath -m "$scriptAbsoluteFolder" 2> /dev/null)
        [[ -n "$scriptLocal" ]] && scriptlocal_win=$(cygpath -m "$scriptLocal" 2> /dev/null)
        _install_certs_log "cygwin root: ${cyg_root:-unknown}"
        _install_certs_log "bash path: ${bash_win:-$bash_path}"
        _install_certs_log "scriptAbsoluteFolder: ${saf_win:-$scriptAbsoluteFolder}"
        _install_certs_log "scriptLocal: ${scriptlocal_win:-$scriptLocal}"
        _install_certs_log "PWD: $(pwd)"
        _install_certs_log "uname: $(uname -a)"
        _install_certs_log "sessionid: ${sessionid:-unset}"
    }

    _install_certs_remove_known_offenders() {
        _if_cygwin || return 0
        local known_paths=(
            "$cert_link_dir/ca-bundle.crt.lnk"
            "$cert_link_dir/ca-bundle.crt"
        )
        _install_certs_log 'checking known legacy cert links'
        local path
        for path in "${known_paths[@]}"
        do
            [[ -e "$path" ]] || continue
            _messagePlain_warn "force-remove: legacy cert link: $path"
            _install_certs_log "force remove legacy link: $path"
            rm -f "$path"
        done
    }

    _install_certs_remove_existing_links() {
        _if_cygwin || return 0
        [[ -d "$cert_link_dir" ]] || return 0
        [[ -d "$anchors_dir" ]] || return 0
        if ! type openssl > /dev/null 2>&1
        then
            _messagePlain_warn 'cert link cleanup skipped: missing openssl'
            _install_certs_log 'cert link cleanup skipped: missing openssl'
            return 0
        fi

        [[ -n "$removed_hash_manifest" ]] || removed_hash_manifest=$(mktemp -t ubcerts_removed_hash.XXXXXX 2> /dev/null || echo "")
        if [[ -z "$removed_hash_manifest" ]]
        then
            _messagePlain_warn 'cert link cleanup skipped: mktemp failed'
            _install_certs_log 'cert link cleanup skipped: mktemp failed'
            return 0
        fi

        _install_certs_log "begin dynamic cert cleanup: anchors=$anchors_dir cert_links=$cert_link_dir"

        while IFS= read -r -d '' anchor_file
        do
            local anchor_hash
            anchor_hash=$(openssl x509 -noout -hash -in "$anchor_file" 2> /dev/null)
            [[ -z "$anchor_hash" ]] && continue

            local removed_any="false"
            while IFS= read -r -d '' existing_link
            do
                removed_any="true"
                _messagePlain_nominal "cert link remove: $existing_link (hash $anchor_hash, anchor $anchor_file)"
                _install_certs_log "cert link remove: $existing_link (hash $anchor_hash, anchor $anchor_file)"
                rm -f "$existing_link"
            done < <(find "$cert_link_dir" -maxdepth 1 \
                \( -name "$anchor_hash.*" -o -name "$anchor_hash.*.lnk" \) \
                -print0 2> /dev/null)

            if [[ "$removed_any" == "true" ]] && [[ -n "$removed_hash_manifest" ]]
            then
                printf '%s|%s\n' "$anchor_hash" "$anchor_file" >> "$removed_hash_manifest"
            fi
        done < <(find "$anchors_dir" -type f -name '*.crt' -print0 2> /dev/null)

        _install_certs_log 'dynamic cert cleanup complete'
    }

    _install_certs_log_replacements() {
        _if_cygwin || return 0
        [[ -n "$removed_hash_manifest" ]] || return 0
        [[ -s "$removed_hash_manifest" ]] || return 0
        [[ -d "$cert_link_dir" ]] || return 0

        while IFS='|' read -r logged_hash logged_anchor
        do
            [[ -z "$logged_hash" ]] && continue
            while IFS= read -r -d '' recreated_link
            do
                local recreated_target
                recreated_target=$(readlink -f "$recreated_link" 2> /dev/null)
                [[ -z "$recreated_target" ]] && recreated_target="$logged_anchor"
                _messagePlain_good "cert link create: $recreated_link -> $recreated_target (hash $logged_hash)"
                _install_certs_log "cert link create: $recreated_link -> $recreated_target (hash $logged_hash)"
            done < <(find "$cert_link_dir" -maxdepth 1 -name "$logged_hash.*" -print0 2> /dev/null)
        done < "$removed_hash_manifest"
    }
    _install_certs_init_logging
    _install_certs_log_identity

    _if_cygwin && _install_certs_remove_known_offenders
    _if_cygwin && _install_certs_remove_existing_links


    if ! _install_certs_write
    then
        _messagePlain_warn 'cert payloads missing; no files copied'
        _install_certs_log 'cert payloads missing; no files copied'
    fi

    while pgrep '^dpkg$' > /dev/null 2>&1
    do
        sleep 1
    done

    local currentExitStatus="1"
    if ! _if_cygwin
    then
        _install_certs_log 'running update-ca-certificates'
        if sudo -n update-ca-certificates
        then
            currentExitStatus="0"
            _install_certs_log 'update-ca-certificates succeeded'
        else
            local update_status="$?"
            _install_certs_log "update-ca-certificates failed: exit $update_status"
        fi
    fi
    if _if_cygwin
    then
        _install_certs_log 'running update-ca-trust'
        if sudo -n update-ca-trust
        then
            currentExitStatus="0"
            _install_certs_log 'update-ca-trust succeeded'
        else
            local cyg_status="$?"
            _install_certs_log "update-ca-trust failed: exit $cyg_status"
        fi
    fi

    _install_certs_log_replacements

    [[ -n "$removed_hash_manifest" ]] && rm -f "$removed_hash_manifest"
    [[ "$cert_log_enabled" == "true" && -n "$cert_log_file" ]] && _install_certs_log "=== _install_certs end: status $currentExitStatus ==="

    return "$currentExitStatus"
}
