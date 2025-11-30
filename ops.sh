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
    local removed_links_manifest=""

    _install_certs_remove_existing_links() {
        _if_cygwin || return 0
        [[ -d "$cert_link_dir" ]] || return 0
        [[ -d "$anchors_dir" ]] || return 0

        local anchor_targets_manifest
        anchor_targets_manifest=$(mktemp -t ubcerts_anchor.XXXXXX 2> /dev/null) || anchor_targets_manifest=""
        if [[ -z "$anchor_targets_manifest" ]]
        then
            _messagePlain_warn 'cert link cleanup skipped: mktemp failed'
            return 0
        fi
        > "$anchor_targets_manifest"
        while IFS= read -r -d '' anchor_file
        do
            local real_anchor
            real_anchor=$(readlink -f "$anchor_file" 2> /dev/null)
            [[ -z "$real_anchor" ]] && continue
            printf '%s\n' "$real_anchor" >> "$anchor_targets_manifest"
        done < <(find "$anchors_dir" -type f -name '*.crt' -print0 2> /dev/null)

        if [[ ! -s "$anchor_targets_manifest" ]]
        then
            rm -f "$anchor_targets_manifest"
            return 0
        fi

        [[ -n "$removed_links_manifest" ]] || removed_links_manifest=$(mktemp -t ubcerts_removed.XXXXXX 2> /dev/null || echo "")

        while IFS= read -r -d '' link_path
        do
            local link_target
            link_target=$(readlink -f "$link_path" 2> /dev/null)
            [[ -z "$link_target" ]] && continue
            if grep -Fxq "$link_target" "$anchor_targets_manifest"
            then
                _messagePlain_nominal 'cert link remove: '"$link_path"' -> '"$link_target"
                if [[ -n "$removed_links_manifest" ]]
                then
                    printf '%s\n' "$link_target" >> "$removed_links_manifest"
                fi
                rm -f "$link_path"
            fi
        done < <(find "$cert_link_dir" -maxdepth 1 -type l -name '*.*' -print0 2> /dev/null)

        rm -f "$anchor_targets_manifest"
    }

    _install_certs_log_replacements() {
        _if_cygwin || return 0
        [[ -n "$removed_links_manifest" ]] || return 0
        [[ -s "$removed_links_manifest" ]] || return 0
        [[ -d "$cert_link_dir" ]] || return 0

        while IFS= read -r -d '' link_path
        do
            local link_target
            link_target=$(readlink -f "$link_path" 2> /dev/null)
            [[ -z "$link_target" ]] && continue
            if grep -Fxq "$link_target" "$removed_links_manifest"
            then
                _messagePlain_good 'cert link create: '"$link_path"' -> '"$link_target"
            fi
        done < <(find "$cert_link_dir" -maxdepth 1 -type l -name '*.*' -print0 2> /dev/null)
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

    [[ -n "$removed_links_manifest" ]] && rm -f "$removed_links_manifest"

    return "$currentExitStatus"
}
