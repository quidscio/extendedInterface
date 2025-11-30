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

    _install_certs_remove_existing_links() {
        _if_cygwin || return 0
        [[ -d "$cert_link_dir" ]] || return 0
        [[ -d "$anchors_dir" ]] || return 0
        if ! type openssl > /dev/null 2>&1
        then
            _messagePlain_warn 'cert link cleanup skipped: missing openssl'
            return 0
        fi

        [[ -n "$removed_hash_manifest" ]] || removed_hash_manifest=$(mktemp -t ubcerts_removed_hash.XXXXXX 2> /dev/null || echo "")

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
                rm -f "$existing_link"
            done < <(find "$cert_link_dir" -maxdepth 1 \
                \( -name "$anchor_hash.*" -o -name "$anchor_hash.*.lnk" \) \
                -print0 2> /dev/null)

            if [[ "$removed_any" == "true" ]] && [[ -n "$removed_hash_manifest" ]]
            then
                printf '%s|%s\n' "$anchor_hash" "$anchor_file" >> "$removed_hash_manifest"
            fi
        done < <(find "$anchors_dir" -type f -name '*.crt' -print0 2> /dev/null)
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
            done < <(find "$cert_link_dir" -maxdepth 1 -name "$logged_hash.*" -print0 2> /dev/null)
        done < "$removed_hash_manifest"
    }


    _if_cygwin && _install_certs_remove_existing_links


    _install_certs_write

    while pgrep '^dpkg$' > /dev/null 2>&1
    do
        sleep 1
    done

    local currentExitStatus="1"
    ! _if_cygwin && sudo -n update-ca-certificates
    [[ "$?" == "0" ]] && currentExitStatus="0"
    _if_cygwin && sudo -n update-ca-trust
    [[ "$?" == "0" ]] && currentExitStatus="0"

    _install_certs_log_replacements

    [[ -n "$removed_hash_manifest" ]] && rm -f "$removed_hash_manifest"

    return "$currentExitStatus"
}
