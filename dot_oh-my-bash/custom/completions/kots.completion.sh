# bash completion for kots                                 -*- shell-script -*-

__kots_debug()
{
    if [[ -n ${BASH_COMP_DEBUG_FILE:-} ]]; then
        echo "$*" >> "${BASH_COMP_DEBUG_FILE}"
    fi
}

# Homebrew on Macs have version 1.3 of bash-completion which doesn't include
# _init_completion. This is a very minimal version of that function.
__kots_init_completion()
{
    COMPREPLY=()
    _get_comp_words_by_ref "$@" cur prev words cword
}

__kots_index_of_word()
{
    local w word=$1
    shift
    index=0
    for w in "$@"; do
        [[ $w = "$word" ]] && return
        index=$((index+1))
    done
    index=-1
}

__kots_contains_word()
{
    local w word=$1; shift
    for w in "$@"; do
        [[ $w = "$word" ]] && return
    done
    return 1
}

__kots_handle_go_custom_completion()
{
    __kots_debug "${FUNCNAME[0]}: cur is ${cur}, words[*] is ${words[*]}, #words[@] is ${#words[@]}"

    local shellCompDirectiveError=1
    local shellCompDirectiveNoSpace=2
    local shellCompDirectiveNoFileComp=4
    local shellCompDirectiveFilterFileExt=8
    local shellCompDirectiveFilterDirs=16

    local out requestComp lastParam lastChar comp directive args

    # Prepare the command to request completions for the program.
    # Calling ${words[0]} instead of directly kots allows to handle aliases
    args=("${words[@]:1}")
    # Disable ActiveHelp which is not supported for bash completion v1
    requestComp="KOTS_ACTIVE_HELP=0 ${words[0]} __completeNoDesc ${args[*]}"

    lastParam=${words[$((${#words[@]}-1))]}
    lastChar=${lastParam:$((${#lastParam}-1)):1}
    __kots_debug "${FUNCNAME[0]}: lastParam ${lastParam}, lastChar ${lastChar}"

    if [ -z "${cur}" ] && [ "${lastChar}" != "=" ]; then
        # If the last parameter is complete (there is a space following it)
        # We add an extra empty parameter so we can indicate this to the go method.
        __kots_debug "${FUNCNAME[0]}: Adding extra empty parameter"
        requestComp="${requestComp} \"\""
    fi

    __kots_debug "${FUNCNAME[0]}: calling ${requestComp}"
    # Use eval to handle any environment variables and such
    out=$(eval "${requestComp}" 2>/dev/null)

    # Extract the directive integer at the very end of the output following a colon (:)
    directive=${out##*:}
    # Remove the directive
    out=${out%:*}
    if [ "${directive}" = "${out}" ]; then
        # There is not directive specified
        directive=0
    fi
    __kots_debug "${FUNCNAME[0]}: the completion directive is: ${directive}"
    __kots_debug "${FUNCNAME[0]}: the completions are: ${out}"

    if [ $((directive & shellCompDirectiveError)) -ne 0 ]; then
        # Error code.  No completion.
        __kots_debug "${FUNCNAME[0]}: received error from custom completion go code"
        return
    else
        if [ $((directive & shellCompDirectiveNoSpace)) -ne 0 ]; then
            if [[ $(type -t compopt) = "builtin" ]]; then
                __kots_debug "${FUNCNAME[0]}: activating no space"
                compopt -o nospace
            fi
        fi
        if [ $((directive & shellCompDirectiveNoFileComp)) -ne 0 ]; then
            if [[ $(type -t compopt) = "builtin" ]]; then
                __kots_debug "${FUNCNAME[0]}: activating no file completion"
                compopt +o default
            fi
        fi
    fi

    if [ $((directive & shellCompDirectiveFilterFileExt)) -ne 0 ]; then
        # File extension filtering
        local fullFilter filter filteringCmd
        # Do not use quotes around the $out variable or else newline
        # characters will be kept.
        for filter in ${out}; do
            fullFilter+="$filter|"
        done

        filteringCmd="_filedir $fullFilter"
        __kots_debug "File filtering command: $filteringCmd"
        $filteringCmd
    elif [ $((directive & shellCompDirectiveFilterDirs)) -ne 0 ]; then
        # File completion for directories only
        local subdir
        # Use printf to strip any trailing newline
        subdir=$(printf "%s" "${out}")
        if [ -n "$subdir" ]; then
            __kots_debug "Listing directories in $subdir"
            __kots_handle_subdirs_in_dir_flag "$subdir"
        else
            __kots_debug "Listing directories in ."
            _filedir -d
        fi
    else
        while IFS='' read -r comp; do
            COMPREPLY+=("$comp")
        done < <(compgen -W "${out}" -- "$cur")
    fi
}

__kots_handle_reply()
{
    __kots_debug "${FUNCNAME[0]}"
    local comp
    case $cur in
        -*)
            if [[ $(type -t compopt) = "builtin" ]]; then
                compopt -o nospace
            fi
            local allflags
            if [ ${#must_have_one_flag[@]} -ne 0 ]; then
                allflags=("${must_have_one_flag[@]}")
            else
                allflags=("${flags[*]} ${two_word_flags[*]}")
            fi
            while IFS='' read -r comp; do
                COMPREPLY+=("$comp")
            done < <(compgen -W "${allflags[*]}" -- "$cur")
            if [[ $(type -t compopt) = "builtin" ]]; then
                [[ "${COMPREPLY[0]}" == *= ]] || compopt +o nospace
            fi

            # complete after --flag=abc
            if [[ $cur == *=* ]]; then
                if [[ $(type -t compopt) = "builtin" ]]; then
                    compopt +o nospace
                fi

                local index flag
                flag="${cur%=*}"
                __kots_index_of_word "${flag}" "${flags_with_completion[@]}"
                COMPREPLY=()
                if [[ ${index} -ge 0 ]]; then
                    PREFIX=""
                    cur="${cur#*=}"
                    ${flags_completion[${index}]}
                    if [ -n "${ZSH_VERSION:-}" ]; then
                        # zsh completion needs --flag= prefix
                        eval "COMPREPLY=( \"\${COMPREPLY[@]/#/${flag}=}\" )"
                    fi
                fi
            fi

            if [[ -z "${flag_parsing_disabled}" ]]; then
                # If flag parsing is enabled, we have completed the flags and can return.
                # If flag parsing is disabled, we may not know all (or any) of the flags, so we fallthrough
                # to possibly call handle_go_custom_completion.
                return 0;
            fi
            ;;
    esac

    # check if we are handling a flag with special work handling
    local index
    __kots_index_of_word "${prev}" "${flags_with_completion[@]}"
    if [[ ${index} -ge 0 ]]; then
        ${flags_completion[${index}]}
        return
    fi

    # we are parsing a flag and don't have a special handler, no completion
    if [[ ${cur} != "${words[cword]}" ]]; then
        return
    fi

    local completions
    completions=("${commands[@]}")
    if [[ ${#must_have_one_noun[@]} -ne 0 ]]; then
        completions+=("${must_have_one_noun[@]}")
    elif [[ -n "${has_completion_function}" ]]; then
        # if a go completion function is provided, defer to that function
        __kots_handle_go_custom_completion
    fi
    if [[ ${#must_have_one_flag[@]} -ne 0 ]]; then
        completions+=("${must_have_one_flag[@]}")
    fi
    while IFS='' read -r comp; do
        COMPREPLY+=("$comp")
    done < <(compgen -W "${completions[*]}" -- "$cur")

    if [[ ${#COMPREPLY[@]} -eq 0 && ${#noun_aliases[@]} -gt 0 && ${#must_have_one_noun[@]} -ne 0 ]]; then
        while IFS='' read -r comp; do
            COMPREPLY+=("$comp")
        done < <(compgen -W "${noun_aliases[*]}" -- "$cur")
    fi

    if [[ ${#COMPREPLY[@]} -eq 0 ]]; then
        if declare -F __kots_custom_func >/dev/null; then
            # try command name qualified custom func
            __kots_custom_func
        else
            # otherwise fall back to unqualified for compatibility
            declare -F __custom_func >/dev/null && __custom_func
        fi
    fi

    # available in bash-completion >= 2, not always present on macOS
    if declare -F __ltrim_colon_completions >/dev/null; then
        __ltrim_colon_completions "$cur"
    fi

    # If there is only 1 completion and it is a flag with an = it will be completed
    # but we don't want a space after the =
    if [[ "${#COMPREPLY[@]}" -eq "1" ]] && [[ $(type -t compopt) = "builtin" ]] && [[ "${COMPREPLY[0]}" == --*= ]]; then
       compopt -o nospace
    fi
}

# The arguments should be in the form "ext1|ext2|extn"
__kots_handle_filename_extension_flag()
{
    local ext="$1"
    _filedir "@(${ext})"
}

__kots_handle_subdirs_in_dir_flag()
{
    local dir="$1"
    pushd "${dir}" >/dev/null 2>&1 && _filedir -d && popd >/dev/null 2>&1 || return
}

__kots_handle_flag()
{
    __kots_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

    # if a command required a flag, and we found it, unset must_have_one_flag()
    local flagname=${words[c]}
    local flagvalue=""
    # if the word contained an =
    if [[ ${words[c]} == *"="* ]]; then
        flagvalue=${flagname#*=} # take in as flagvalue after the =
        flagname=${flagname%=*} # strip everything after the =
        flagname="${flagname}=" # but put the = back
    fi
    __kots_debug "${FUNCNAME[0]}: looking for ${flagname}"
    if __kots_contains_word "${flagname}" "${must_have_one_flag[@]}"; then
        must_have_one_flag=()
    fi

    # if you set a flag which only applies to this command, don't show subcommands
    if __kots_contains_word "${flagname}" "${local_nonpersistent_flags[@]}"; then
      commands=()
    fi

    # keep flag value with flagname as flaghash
    # flaghash variable is an associative array which is only supported in bash > 3.
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        if [ -n "${flagvalue}" ] ; then
            flaghash[${flagname}]=${flagvalue}
        elif [ -n "${words[ $((c+1)) ]}" ] ; then
            flaghash[${flagname}]=${words[ $((c+1)) ]}
        else
            flaghash[${flagname}]="true" # pad "true" for bool flag
        fi
    fi

    # skip the argument to a two word flag
    if [[ ${words[c]} != *"="* ]] && __kots_contains_word "${words[c]}" "${two_word_flags[@]}"; then
        __kots_debug "${FUNCNAME[0]}: found a flag ${words[c]}, skip the next argument"
        c=$((c+1))
        # if we are looking for a flags value, don't show commands
        if [[ $c -eq $cword ]]; then
            commands=()
        fi
    fi

    c=$((c+1))

}

__kots_handle_noun()
{
    __kots_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

    if __kots_contains_word "${words[c]}" "${must_have_one_noun[@]}"; then
        must_have_one_noun=()
    elif __kots_contains_word "${words[c]}" "${noun_aliases[@]}"; then
        must_have_one_noun=()
    fi

    nouns+=("${words[c]}")
    c=$((c+1))
}

__kots_handle_command()
{
    __kots_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

    local next_command
    if [[ -n ${last_command} ]]; then
        next_command="_${last_command}_${words[c]//:/__}"
    else
        if [[ $c -eq 0 ]]; then
            next_command="_kots_root_command"
        else
            next_command="_${words[c]//:/__}"
        fi
    fi
    c=$((c+1))
    __kots_debug "${FUNCNAME[0]}: looking for ${next_command}"
    declare -F "$next_command" >/dev/null && $next_command
}

__kots_handle_word()
{
    if [[ $c -ge $cword ]]; then
        __kots_handle_reply
        return
    fi
    __kots_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"
    if [[ "${words[c]}" == -* ]]; then
        __kots_handle_flag
    elif __kots_contains_word "${words[c]}" "${commands[@]}"; then
        __kots_handle_command
    elif [[ $c -eq 0 ]]; then
        __kots_handle_command
    elif __kots_contains_word "${words[c]}" "${command_aliases[@]}"; then
        # aliashash variable is an associative array which is only supported in bash > 3.
        if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
            words[c]=${aliashash[${words[c]}]}
            __kots_handle_command
        else
            __kots_handle_noun
        fi
    else
        __kots_handle_noun
    fi
    __kots_handle_word
}

_kots_admin-console_garbage-collect-images()
{
    last_command="kots_admin-console_garbage-collect-images"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--ignore-rollback")
    local_nonpersistent_flags+=("--ignore-rollback")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_admin-console_generate-manifests()
{
    last_command="kots_admin-console_generate-manifests"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--additional-namespaces=")
    two_word_flags+=("--additional-namespaces")
    local_nonpersistent_flags+=("--additional-namespaces")
    local_nonpersistent_flags+=("--additional-namespaces=")
    flags+=("--http-proxy=")
    two_word_flags+=("--http-proxy")
    local_nonpersistent_flags+=("--http-proxy")
    local_nonpersistent_flags+=("--http-proxy=")
    flags+=("--https-proxy=")
    two_word_flags+=("--https-proxy")
    local_nonpersistent_flags+=("--https-proxy")
    local_nonpersistent_flags+=("--https-proxy=")
    flags+=("--kotsadm-namespace=")
    two_word_flags+=("--kotsadm-namespace")
    local_nonpersistent_flags+=("--kotsadm-namespace")
    local_nonpersistent_flags+=("--kotsadm-namespace=")
    flags+=("--kotsadm-registry=")
    two_word_flags+=("--kotsadm-registry")
    local_nonpersistent_flags+=("--kotsadm-registry")
    local_nonpersistent_flags+=("--kotsadm-registry=")
    flags+=("--minimal-rbac")
    local_nonpersistent_flags+=("--minimal-rbac")
    flags+=("--no-proxy=")
    two_word_flags+=("--no-proxy")
    local_nonpersistent_flags+=("--no-proxy")
    local_nonpersistent_flags+=("--no-proxy=")
    flags+=("--registry-password=")
    two_word_flags+=("--registry-password")
    local_nonpersistent_flags+=("--registry-password")
    local_nonpersistent_flags+=("--registry-password=")
    flags+=("--registry-username=")
    two_word_flags+=("--registry-username")
    local_nonpersistent_flags+=("--registry-username")
    local_nonpersistent_flags+=("--registry-username=")
    flags+=("--rootdir=")
    two_word_flags+=("--rootdir")
    local_nonpersistent_flags+=("--rootdir")
    local_nonpersistent_flags+=("--rootdir=")
    flags+=("--shared-password=")
    two_word_flags+=("--shared-password")
    local_nonpersistent_flags+=("--shared-password")
    local_nonpersistent_flags+=("--shared-password=")
    flags+=("--with-minio")
    local_nonpersistent_flags+=("--with-minio")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_admin-console_push-images()
{
    last_command="kots_admin-console_push-images"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--registry-password=")
    two_word_flags+=("--registry-password")
    local_nonpersistent_flags+=("--registry-password")
    local_nonpersistent_flags+=("--registry-password=")
    flags+=("--registry-username=")
    two_word_flags+=("--registry-username")
    local_nonpersistent_flags+=("--registry-username")
    local_nonpersistent_flags+=("--registry-username=")
    flags+=("--skip-registry-check")
    local_nonpersistent_flags+=("--skip-registry-check")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_admin-console_upgrade()
{
    last_command="kots_admin-console_upgrade"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--ensure-rbac")
    local_nonpersistent_flags+=("--ensure-rbac")
    flags+=("--kotsadm-namespace=")
    two_word_flags+=("--kotsadm-namespace")
    local_nonpersistent_flags+=("--kotsadm-namespace")
    local_nonpersistent_flags+=("--kotsadm-namespace=")
    flags+=("--kotsadm-registry=")
    two_word_flags+=("--kotsadm-registry")
    local_nonpersistent_flags+=("--kotsadm-registry")
    local_nonpersistent_flags+=("--kotsadm-registry=")
    flags+=("--registry-password=")
    two_word_flags+=("--registry-password")
    local_nonpersistent_flags+=("--registry-password")
    local_nonpersistent_flags+=("--registry-password=")
    flags+=("--registry-username=")
    two_word_flags+=("--registry-username")
    local_nonpersistent_flags+=("--registry-username")
    local_nonpersistent_flags+=("--registry-username=")
    flags+=("--skip-rbac-check")
    local_nonpersistent_flags+=("--skip-rbac-check")
    flags+=("--strict-security-context")
    local_nonpersistent_flags+=("--strict-security-context")
    flags+=("--wait-duration=")
    two_word_flags+=("--wait-duration")
    local_nonpersistent_flags+=("--wait-duration")
    local_nonpersistent_flags+=("--wait-duration=")
    flags+=("--with-minio")
    local_nonpersistent_flags+=("--with-minio")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_admin-console()
{
    last_command="kots_admin-console"

    command_aliases=()

    commands=()
    commands+=("garbage-collect-images")
    commands+=("generate-manifests")
    commands+=("push-images")
    commands+=("upgrade")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--port=")
    two_word_flags+=("--port")
    local_nonpersistent_flags+=("--port")
    local_nonpersistent_flags+=("--port=")
    flags+=("--wait-duration=")
    two_word_flags+=("--wait-duration")
    local_nonpersistent_flags+=("--wait-duration")
    local_nonpersistent_flags+=("--wait-duration=")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_backup_ls()
{
    last_command="kots_backup_ls"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_backup()
{
    last_command="kots_backup"

    command_aliases=()

    commands=()
    commands+=("ls")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--wait")
    local_nonpersistent_flags+=("--wait")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_completion()
{
    last_command="kots_completion"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--help")
    flags+=("-h")
    local_nonpersistent_flags+=("--help")
    local_nonpersistent_flags+=("-h")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    must_have_one_noun+=("bash")
    must_have_one_noun+=("fish")
    must_have_one_noun+=("powershell")
    must_have_one_noun+=("zsh")
    noun_aliases=()
}

_kots_docker_ensure-secret()
{
    last_command="kots_docker_ensure-secret"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--dockerhub-password=")
    two_word_flags+=("--dockerhub-password")
    local_nonpersistent_flags+=("--dockerhub-password")
    local_nonpersistent_flags+=("--dockerhub-password=")
    flags+=("--dockerhub-username=")
    two_word_flags+=("--dockerhub-username")
    local_nonpersistent_flags+=("--dockerhub-username")
    local_nonpersistent_flags+=("--dockerhub-username=")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_docker()
{
    last_command="kots_docker"

    command_aliases=()

    commands=()
    commands+=("ensure-secret")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_download()
{
    last_command="kots_download"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--decrypt-password-values")
    local_nonpersistent_flags+=("--decrypt-password-values")
    flags+=("--dest=")
    two_word_flags+=("--dest")
    local_nonpersistent_flags+=("--dest")
    local_nonpersistent_flags+=("--dest=")
    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--overwrite")
    local_nonpersistent_flags+=("--overwrite")
    flags+=("--slug=")
    two_word_flags+=("--slug")
    local_nonpersistent_flags+=("--slug")
    local_nonpersistent_flags+=("--slug=")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_enable-ha()
{
    last_command="kots_enable-ha"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--wait-duration=")
    two_word_flags+=("--wait-duration")
    local_nonpersistent_flags+=("--wait-duration")
    local_nonpersistent_flags+=("--wait-duration=")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_get_apps()
{
    last_command="kots_get_apps"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_get_backups()
{
    last_command="kots_get_backups"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_get_config()
{
    last_command="kots_get_config"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--appslug=")
    two_word_flags+=("--appslug")
    local_nonpersistent_flags+=("--appslug")
    local_nonpersistent_flags+=("--appslug=")
    flags+=("--decrypt")
    local_nonpersistent_flags+=("--decrypt")
    flags+=("--sequence=")
    two_word_flags+=("--sequence")
    local_nonpersistent_flags+=("--sequence")
    local_nonpersistent_flags+=("--sequence=")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_get_restores()
{
    last_command="kots_get_restores"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_get_versions()
{
    last_command="kots_get_versions"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--current-page=")
    two_word_flags+=("--current-page")
    local_nonpersistent_flags+=("--current-page")
    local_nonpersistent_flags+=("--current-page=")
    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--page-size=")
    two_word_flags+=("--page-size")
    local_nonpersistent_flags+=("--page-size")
    local_nonpersistent_flags+=("--page-size=")
    flags+=("--pin-latest")
    local_nonpersistent_flags+=("--pin-latest")
    flags+=("--pin-latest-deployable")
    local_nonpersistent_flags+=("--pin-latest-deployable")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_get()
{
    last_command="kots_get"

    command_aliases=()

    commands=()
    commands+=("apps")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("app")
        aliashash["app"]="apps"
    fi
    commands+=("backups")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("backup")
        aliashash["backup"]="backups"
    fi
    commands+=("config")
    commands+=("restores")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("restore")
        aliashash["restore"]="restores"
    fi
    commands+=("versions")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_help()
{
    last_command="kots_help"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_kots_install()
{
    last_command="kots_install"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--airgap")
    local_nonpersistent_flags+=("--airgap")
    flags+=("--airgap-bundle=")
    two_word_flags+=("--airgap-bundle")
    local_nonpersistent_flags+=("--airgap-bundle")
    local_nonpersistent_flags+=("--airgap-bundle=")
    flags+=("--app-version-label=")
    two_word_flags+=("--app-version-label")
    local_nonpersistent_flags+=("--app-version-label")
    local_nonpersistent_flags+=("--app-version-label=")
    flags+=("--config-values=")
    two_word_flags+=("--config-values")
    local_nonpersistent_flags+=("--config-values")
    local_nonpersistent_flags+=("--config-values=")
    flags+=("--copy-proxy-env")
    local_nonpersistent_flags+=("--copy-proxy-env")
    flags+=("--disable-image-push")
    local_nonpersistent_flags+=("--disable-image-push")
    flags+=("--ensure-rbac")
    local_nonpersistent_flags+=("--ensure-rbac")
    flags+=("--http-proxy=")
    two_word_flags+=("--http-proxy")
    local_nonpersistent_flags+=("--http-proxy")
    local_nonpersistent_flags+=("--http-proxy=")
    flags+=("--https-proxy=")
    two_word_flags+=("--https-proxy")
    local_nonpersistent_flags+=("--https-proxy")
    local_nonpersistent_flags+=("--https-proxy=")
    flags+=("--kotsadm-namespace=")
    two_word_flags+=("--kotsadm-namespace")
    local_nonpersistent_flags+=("--kotsadm-namespace")
    local_nonpersistent_flags+=("--kotsadm-namespace=")
    flags+=("--kotsadm-registry=")
    two_word_flags+=("--kotsadm-registry")
    local_nonpersistent_flags+=("--kotsadm-registry")
    local_nonpersistent_flags+=("--kotsadm-registry=")
    flags+=("--license-file=")
    two_word_flags+=("--license-file")
    local_nonpersistent_flags+=("--license-file")
    local_nonpersistent_flags+=("--license-file=")
    flags+=("--local-path=")
    two_word_flags+=("--local-path")
    local_nonpersistent_flags+=("--local-path")
    local_nonpersistent_flags+=("--local-path=")
    flags+=("--name=")
    two_word_flags+=("--name")
    local_nonpersistent_flags+=("--name")
    local_nonpersistent_flags+=("--name=")
    flags+=("--no-port-forward")
    local_nonpersistent_flags+=("--no-port-forward")
    flags+=("--no-proxy=")
    two_word_flags+=("--no-proxy")
    local_nonpersistent_flags+=("--no-proxy")
    local_nonpersistent_flags+=("--no-proxy=")
    flags+=("--port=")
    two_word_flags+=("--port")
    local_nonpersistent_flags+=("--port")
    local_nonpersistent_flags+=("--port=")
    flags+=("--preflights-wait-duration=")
    two_word_flags+=("--preflights-wait-duration")
    local_nonpersistent_flags+=("--preflights-wait-duration")
    local_nonpersistent_flags+=("--preflights-wait-duration=")
    flags+=("--registry-password=")
    two_word_flags+=("--registry-password")
    local_nonpersistent_flags+=("--registry-password")
    local_nonpersistent_flags+=("--registry-password=")
    flags+=("--registry-username=")
    two_word_flags+=("--registry-username")
    local_nonpersistent_flags+=("--registry-username")
    local_nonpersistent_flags+=("--registry-username=")
    flags+=("--repo=")
    two_word_flags+=("--repo")
    local_nonpersistent_flags+=("--repo")
    local_nonpersistent_flags+=("--repo=")
    flags+=("--set=")
    two_word_flags+=("--set")
    local_nonpersistent_flags+=("--set")
    local_nonpersistent_flags+=("--set=")
    flags+=("--shared-password=")
    two_word_flags+=("--shared-password")
    local_nonpersistent_flags+=("--shared-password")
    local_nonpersistent_flags+=("--shared-password=")
    flags+=("--skip-compatibility-check")
    local_nonpersistent_flags+=("--skip-compatibility-check")
    flags+=("--skip-preflights")
    local_nonpersistent_flags+=("--skip-preflights")
    flags+=("--skip-rbac-check")
    local_nonpersistent_flags+=("--skip-rbac-check")
    flags+=("--skip-registry-check")
    local_nonpersistent_flags+=("--skip-registry-check")
    flags+=("--strict-security-context")
    local_nonpersistent_flags+=("--strict-security-context")
    flags+=("--use-minimal-rbac")
    local_nonpersistent_flags+=("--use-minimal-rbac")
    flags+=("--wait-duration=")
    two_word_flags+=("--wait-duration")
    local_nonpersistent_flags+=("--wait-duration")
    local_nonpersistent_flags+=("--wait-duration=")
    flags+=("--with-minio")
    local_nonpersistent_flags+=("--with-minio")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_pull()
{
    last_command="kots_pull"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--config-values=")
    two_word_flags+=("--config-values")
    local_nonpersistent_flags+=("--config-values")
    local_nonpersistent_flags+=("--config-values=")
    flags+=("--copy-proxy-env")
    local_nonpersistent_flags+=("--copy-proxy-env")
    flags+=("--downstream=")
    two_word_flags+=("--downstream")
    local_nonpersistent_flags+=("--downstream")
    local_nonpersistent_flags+=("--downstream=")
    flags+=("--exclude-admin-console")
    local_nonpersistent_flags+=("--exclude-admin-console")
    flags+=("--exclude-kots-kinds")
    local_nonpersistent_flags+=("--exclude-kots-kinds")
    flags+=("--http-proxy=")
    two_word_flags+=("--http-proxy")
    local_nonpersistent_flags+=("--http-proxy")
    local_nonpersistent_flags+=("--http-proxy=")
    flags+=("--https-proxy=")
    two_word_flags+=("--https-proxy")
    local_nonpersistent_flags+=("--https-proxy")
    local_nonpersistent_flags+=("--https-proxy=")
    flags+=("--identity-config=")
    two_word_flags+=("--identity-config")
    local_nonpersistent_flags+=("--identity-config")
    local_nonpersistent_flags+=("--identity-config=")
    flags+=("--image-namespace=")
    two_word_flags+=("--image-namespace")
    local_nonpersistent_flags+=("--image-namespace")
    local_nonpersistent_flags+=("--image-namespace=")
    flags+=("--license-file=")
    two_word_flags+=("--license-file")
    local_nonpersistent_flags+=("--license-file")
    local_nonpersistent_flags+=("--license-file=")
    flags+=("--local-path=")
    two_word_flags+=("--local-path")
    local_nonpersistent_flags+=("--local-path")
    local_nonpersistent_flags+=("--local-path=")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--no-proxy=")
    two_word_flags+=("--no-proxy")
    local_nonpersistent_flags+=("--no-proxy")
    local_nonpersistent_flags+=("--no-proxy=")
    flags+=("--registry-endpoint=")
    two_word_flags+=("--registry-endpoint")
    local_nonpersistent_flags+=("--registry-endpoint")
    local_nonpersistent_flags+=("--registry-endpoint=")
    flags+=("--registry-password=")
    two_word_flags+=("--registry-password")
    local_nonpersistent_flags+=("--registry-password")
    local_nonpersistent_flags+=("--registry-password=")
    flags+=("--registry-username=")
    two_word_flags+=("--registry-username")
    local_nonpersistent_flags+=("--registry-username")
    local_nonpersistent_flags+=("--registry-username=")
    flags+=("--rewrite-images")
    local_nonpersistent_flags+=("--rewrite-images")
    flags+=("--rootdir=")
    two_word_flags+=("--rootdir")
    local_nonpersistent_flags+=("--rootdir")
    local_nonpersistent_flags+=("--rootdir=")
    flags+=("--shared-password=")
    two_word_flags+=("--shared-password")
    local_nonpersistent_flags+=("--shared-password")
    local_nonpersistent_flags+=("--shared-password=")
    flags+=("--skip-compatibility-check")
    local_nonpersistent_flags+=("--skip-compatibility-check")
    flags+=("--with-minio")
    local_nonpersistent_flags+=("--with-minio")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_remove()
{
    last_command="kots_remove"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--force")
    flags+=("-f")
    local_nonpersistent_flags+=("--force")
    local_nonpersistent_flags+=("-f")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--undeploy")
    local_nonpersistent_flags+=("--undeploy")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_reset-password()
{
    last_command="kots_reset-password"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_reset-tls()
{
    last_command="kots_reset-tls"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--accept-anonymous-uploads")
    local_nonpersistent_flags+=("--accept-anonymous-uploads")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_restore_ls()
{
    last_command="kots_restore_ls"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_restore()
{
    last_command="kots_restore"

    command_aliases=()

    commands=()
    commands+=("ls")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--exclude-admin-console")
    local_nonpersistent_flags+=("--exclude-admin-console")
    flags+=("--exclude-apps")
    local_nonpersistent_flags+=("--exclude-apps")
    flags+=("--from-backup=")
    two_word_flags+=("--from-backup")
    local_nonpersistent_flags+=("--from-backup")
    local_nonpersistent_flags+=("--from-backup=")
    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--velero-namespace=")
    two_word_flags+=("--velero-namespace")
    local_nonpersistent_flags+=("--velero-namespace")
    local_nonpersistent_flags+=("--velero-namespace=")
    flags+=("--wait-for-apps")
    local_nonpersistent_flags+=("--wait-for-apps")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_set_config()
{
    last_command="kots_set_config"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--config-file=")
    two_word_flags+=("--config-file")
    local_nonpersistent_flags+=("--config-file")
    local_nonpersistent_flags+=("--config-file=")
    flags+=("--deploy")
    local_nonpersistent_flags+=("--deploy")
    flags+=("--key=")
    two_word_flags+=("--key")
    local_nonpersistent_flags+=("--key")
    local_nonpersistent_flags+=("--key=")
    flags+=("--merge")
    local_nonpersistent_flags+=("--merge")
    flags+=("--skip-preflights")
    local_nonpersistent_flags+=("--skip-preflights")
    flags+=("--value=")
    two_word_flags+=("--value")
    local_nonpersistent_flags+=("--value")
    local_nonpersistent_flags+=("--value=")
    flags+=("--value-from-file=")
    two_word_flags+=("--value-from-file")
    local_nonpersistent_flags+=("--value-from-file")
    local_nonpersistent_flags+=("--value-from-file=")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_set()
{
    last_command="kots_set"

    command_aliases=()

    commands=()
    commands+=("config")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_upload()
{
    last_command="kots_upload"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--deploy")
    local_nonpersistent_flags+=("--deploy")
    flags+=("--name=")
    two_word_flags+=("--name")
    local_nonpersistent_flags+=("--name")
    local_nonpersistent_flags+=("--name=")
    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--skip-preflights")
    local_nonpersistent_flags+=("--skip-preflights")
    flags+=("--slug=")
    two_word_flags+=("--slug")
    local_nonpersistent_flags+=("--slug")
    local_nonpersistent_flags+=("--slug=")
    flags+=("--upstream-uri=")
    two_word_flags+=("--upstream-uri")
    local_nonpersistent_flags+=("--upstream-uri")
    local_nonpersistent_flags+=("--upstream-uri=")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_upstream_download()
{
    last_command="kots_upstream_download"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--sequence=")
    two_word_flags+=("--sequence")
    local_nonpersistent_flags+=("--sequence")
    local_nonpersistent_flags+=("--sequence=")
    flags+=("--skip-compatibility-check")
    local_nonpersistent_flags+=("--skip-compatibility-check")
    flags+=("--skip-preflights")
    local_nonpersistent_flags+=("--skip-preflights")
    flags+=("--wait")
    local_nonpersistent_flags+=("--wait")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_upstream_upgrade()
{
    last_command="kots_upstream_upgrade"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--airgap-bundle=")
    two_word_flags+=("--airgap-bundle")
    local_nonpersistent_flags+=("--airgap-bundle")
    local_nonpersistent_flags+=("--airgap-bundle=")
    flags+=("--deploy")
    local_nonpersistent_flags+=("--deploy")
    flags+=("--deploy-version-label=")
    two_word_flags+=("--deploy-version-label")
    local_nonpersistent_flags+=("--deploy-version-label")
    local_nonpersistent_flags+=("--deploy-version-label=")
    flags+=("--disable-image-push")
    local_nonpersistent_flags+=("--disable-image-push")
    flags+=("--kotsadm-namespace=")
    two_word_flags+=("--kotsadm-namespace")
    local_nonpersistent_flags+=("--kotsadm-namespace")
    local_nonpersistent_flags+=("--kotsadm-namespace=")
    flags+=("--kotsadm-registry=")
    two_word_flags+=("--kotsadm-registry")
    local_nonpersistent_flags+=("--kotsadm-registry")
    local_nonpersistent_flags+=("--kotsadm-registry=")
    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--registry-password=")
    two_word_flags+=("--registry-password")
    local_nonpersistent_flags+=("--registry-password")
    local_nonpersistent_flags+=("--registry-password=")
    flags+=("--registry-username=")
    two_word_flags+=("--registry-username")
    local_nonpersistent_flags+=("--registry-username")
    local_nonpersistent_flags+=("--registry-username=")
    flags+=("--skip-compatibility-check")
    local_nonpersistent_flags+=("--skip-compatibility-check")
    flags+=("--skip-preflights")
    local_nonpersistent_flags+=("--skip-preflights")
    flags+=("--skip-registry-check")
    local_nonpersistent_flags+=("--skip-registry-check")
    flags+=("--wait")
    local_nonpersistent_flags+=("--wait")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_upstream()
{
    last_command="kots_upstream"

    command_aliases=()

    commands=()
    commands+=("download")
    commands+=("upgrade")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_velero_configure-aws-s3_access-key()
{
    last_command="kots_velero_configure-aws-s3_access-key"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--access-key-id=")
    two_word_flags+=("--access-key-id")
    local_nonpersistent_flags+=("--access-key-id")
    local_nonpersistent_flags+=("--access-key-id=")
    flags+=("--bucket=")
    two_word_flags+=("--bucket")
    local_nonpersistent_flags+=("--bucket")
    local_nonpersistent_flags+=("--bucket=")
    flags+=("--path=")
    two_word_flags+=("--path")
    local_nonpersistent_flags+=("--path")
    local_nonpersistent_flags+=("--path=")
    flags+=("--region=")
    two_word_flags+=("--region")
    local_nonpersistent_flags+=("--region")
    local_nonpersistent_flags+=("--region=")
    flags+=("--secret-access-key=")
    two_word_flags+=("--secret-access-key")
    local_nonpersistent_flags+=("--secret-access-key")
    local_nonpersistent_flags+=("--secret-access-key=")
    flags+=("--skip-validation")
    local_nonpersistent_flags+=("--skip-validation")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_flag+=("--access-key-id=")
    must_have_one_flag+=("--bucket=")
    must_have_one_flag+=("--region=")
    must_have_one_flag+=("--secret-access-key=")
    must_have_one_noun=()
    noun_aliases=()
}

_kots_velero_configure-aws-s3_instance-role()
{
    last_command="kots_velero_configure-aws-s3_instance-role"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--bucket=")
    two_word_flags+=("--bucket")
    local_nonpersistent_flags+=("--bucket")
    local_nonpersistent_flags+=("--bucket=")
    flags+=("--path=")
    two_word_flags+=("--path")
    local_nonpersistent_flags+=("--path")
    local_nonpersistent_flags+=("--path=")
    flags+=("--region=")
    two_word_flags+=("--region")
    local_nonpersistent_flags+=("--region")
    local_nonpersistent_flags+=("--region=")
    flags+=("--skip-validation")
    local_nonpersistent_flags+=("--skip-validation")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_flag+=("--bucket=")
    must_have_one_flag+=("--region=")
    must_have_one_noun=()
    noun_aliases=()
}

_kots_velero_configure-aws-s3()
{
    last_command="kots_velero_configure-aws-s3"

    command_aliases=()

    commands=()
    commands+=("access-key")
    commands+=("instance-role")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_velero_configure-azure_service-principle()
{
    last_command="kots_velero_configure-azure_service-principle"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--client-id=")
    two_word_flags+=("--client-id")
    local_nonpersistent_flags+=("--client-id")
    local_nonpersistent_flags+=("--client-id=")
    flags+=("--client-secret=")
    two_word_flags+=("--client-secret")
    local_nonpersistent_flags+=("--client-secret")
    local_nonpersistent_flags+=("--client-secret=")
    flags+=("--cloud-name=")
    two_word_flags+=("--cloud-name")
    local_nonpersistent_flags+=("--cloud-name")
    local_nonpersistent_flags+=("--cloud-name=")
    flags+=("--container=")
    two_word_flags+=("--container")
    local_nonpersistent_flags+=("--container")
    local_nonpersistent_flags+=("--container=")
    flags+=("--path=")
    two_word_flags+=("--path")
    local_nonpersistent_flags+=("--path")
    local_nonpersistent_flags+=("--path=")
    flags+=("--resource-group=")
    two_word_flags+=("--resource-group")
    local_nonpersistent_flags+=("--resource-group")
    local_nonpersistent_flags+=("--resource-group=")
    flags+=("--skip-validation")
    local_nonpersistent_flags+=("--skip-validation")
    flags+=("--storage-account=")
    two_word_flags+=("--storage-account")
    local_nonpersistent_flags+=("--storage-account")
    local_nonpersistent_flags+=("--storage-account=")
    flags+=("--subscription-id=")
    two_word_flags+=("--subscription-id")
    local_nonpersistent_flags+=("--subscription-id")
    local_nonpersistent_flags+=("--subscription-id=")
    flags+=("--tenant-id=")
    two_word_flags+=("--tenant-id")
    local_nonpersistent_flags+=("--tenant-id")
    local_nonpersistent_flags+=("--tenant-id=")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_flag+=("--client-id=")
    must_have_one_flag+=("--client-secret=")
    must_have_one_flag+=("--container=")
    must_have_one_flag+=("--resource-group=")
    must_have_one_flag+=("--storage-account=")
    must_have_one_flag+=("--subscription-id=")
    must_have_one_flag+=("--tenant-id=")
    must_have_one_noun=()
    noun_aliases=()
}

_kots_velero_configure-azure()
{
    last_command="kots_velero_configure-azure"

    command_aliases=()

    commands=()
    commands+=("service-principle")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_velero_configure-gcp_service-account()
{
    last_command="kots_velero_configure-gcp_service-account"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--bucket=")
    two_word_flags+=("--bucket")
    local_nonpersistent_flags+=("--bucket")
    local_nonpersistent_flags+=("--bucket=")
    flags+=("--json-file=")
    two_word_flags+=("--json-file")
    local_nonpersistent_flags+=("--json-file")
    local_nonpersistent_flags+=("--json-file=")
    flags+=("--path=")
    two_word_flags+=("--path")
    local_nonpersistent_flags+=("--path")
    local_nonpersistent_flags+=("--path=")
    flags+=("--skip-validation")
    local_nonpersistent_flags+=("--skip-validation")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_flag+=("--bucket=")
    must_have_one_flag+=("--json-file=")
    must_have_one_noun=()
    noun_aliases=()
}

_kots_velero_configure-gcp_workload-identity()
{
    last_command="kots_velero_configure-gcp_workload-identity"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--bucket=")
    two_word_flags+=("--bucket")
    local_nonpersistent_flags+=("--bucket")
    local_nonpersistent_flags+=("--bucket=")
    flags+=("--path=")
    two_word_flags+=("--path")
    local_nonpersistent_flags+=("--path")
    local_nonpersistent_flags+=("--path=")
    flags+=("--service-account=")
    two_word_flags+=("--service-account")
    local_nonpersistent_flags+=("--service-account")
    local_nonpersistent_flags+=("--service-account=")
    flags+=("--skip-validation")
    local_nonpersistent_flags+=("--skip-validation")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_flag+=("--bucket=")
    must_have_one_flag+=("--service-account=")
    must_have_one_noun=()
    noun_aliases=()
}

_kots_velero_configure-gcp()
{
    last_command="kots_velero_configure-gcp"

    command_aliases=()

    commands=()
    commands+=("service-account")
    commands+=("workload-identity")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_velero_configure-hostpath()
{
    last_command="kots_velero_configure-hostpath"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--force-reset")
    local_nonpersistent_flags+=("--force-reset")
    flags+=("--hostpath=")
    two_word_flags+=("--hostpath")
    local_nonpersistent_flags+=("--hostpath")
    local_nonpersistent_flags+=("--hostpath=")
    flags+=("--kotsadm-namespace=")
    two_word_flags+=("--kotsadm-namespace")
    local_nonpersistent_flags+=("--kotsadm-namespace")
    local_nonpersistent_flags+=("--kotsadm-namespace=")
    flags+=("--kotsadm-registry=")
    two_word_flags+=("--kotsadm-registry")
    local_nonpersistent_flags+=("--kotsadm-registry")
    local_nonpersistent_flags+=("--kotsadm-registry=")
    flags+=("--registry-password=")
    two_word_flags+=("--registry-password")
    local_nonpersistent_flags+=("--registry-password")
    local_nonpersistent_flags+=("--registry-password=")
    flags+=("--registry-username=")
    two_word_flags+=("--registry-username")
    local_nonpersistent_flags+=("--registry-username")
    local_nonpersistent_flags+=("--registry-username=")
    flags+=("--with-minio")
    local_nonpersistent_flags+=("--with-minio")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_velero_configure-internal()
{
    last_command="kots_velero_configure-internal"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--skip-validation")
    local_nonpersistent_flags+=("--skip-validation")
    flags+=("--with-minio")
    local_nonpersistent_flags+=("--with-minio")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_velero_configure-nfs()
{
    last_command="kots_velero_configure-nfs"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--force-reset")
    local_nonpersistent_flags+=("--force-reset")
    flags+=("--kotsadm-namespace=")
    two_word_flags+=("--kotsadm-namespace")
    local_nonpersistent_flags+=("--kotsadm-namespace")
    local_nonpersistent_flags+=("--kotsadm-namespace=")
    flags+=("--kotsadm-registry=")
    two_word_flags+=("--kotsadm-registry")
    local_nonpersistent_flags+=("--kotsadm-registry")
    local_nonpersistent_flags+=("--kotsadm-registry=")
    flags+=("--nfs-path=")
    two_word_flags+=("--nfs-path")
    local_nonpersistent_flags+=("--nfs-path")
    local_nonpersistent_flags+=("--nfs-path=")
    flags+=("--nfs-server=")
    two_word_flags+=("--nfs-server")
    local_nonpersistent_flags+=("--nfs-server")
    local_nonpersistent_flags+=("--nfs-server=")
    flags+=("--registry-password=")
    two_word_flags+=("--registry-password")
    local_nonpersistent_flags+=("--registry-password")
    local_nonpersistent_flags+=("--registry-password=")
    flags+=("--registry-username=")
    two_word_flags+=("--registry-username")
    local_nonpersistent_flags+=("--registry-username")
    local_nonpersistent_flags+=("--registry-username=")
    flags+=("--with-minio")
    local_nonpersistent_flags+=("--with-minio")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_velero_configure-other-s3()
{
    last_command="kots_velero_configure-other-s3"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--access-key-id=")
    two_word_flags+=("--access-key-id")
    local_nonpersistent_flags+=("--access-key-id")
    local_nonpersistent_flags+=("--access-key-id=")
    flags+=("--bucket=")
    two_word_flags+=("--bucket")
    local_nonpersistent_flags+=("--bucket")
    local_nonpersistent_flags+=("--bucket=")
    flags+=("--cacert=")
    two_word_flags+=("--cacert")
    local_nonpersistent_flags+=("--cacert")
    local_nonpersistent_flags+=("--cacert=")
    flags+=("--endpoint=")
    two_word_flags+=("--endpoint")
    local_nonpersistent_flags+=("--endpoint")
    local_nonpersistent_flags+=("--endpoint=")
    flags+=("--kotsadm-namespace=")
    two_word_flags+=("--kotsadm-namespace")
    local_nonpersistent_flags+=("--kotsadm-namespace")
    local_nonpersistent_flags+=("--kotsadm-namespace=")
    flags+=("--kotsadm-registry=")
    two_word_flags+=("--kotsadm-registry")
    local_nonpersistent_flags+=("--kotsadm-registry")
    local_nonpersistent_flags+=("--kotsadm-registry=")
    flags+=("--path=")
    two_word_flags+=("--path")
    local_nonpersistent_flags+=("--path")
    local_nonpersistent_flags+=("--path=")
    flags+=("--region=")
    two_word_flags+=("--region")
    local_nonpersistent_flags+=("--region")
    local_nonpersistent_flags+=("--region=")
    flags+=("--registry-password=")
    two_word_flags+=("--registry-password")
    local_nonpersistent_flags+=("--registry-password")
    local_nonpersistent_flags+=("--registry-password=")
    flags+=("--registry-username=")
    two_word_flags+=("--registry-username")
    local_nonpersistent_flags+=("--registry-username")
    local_nonpersistent_flags+=("--registry-username=")
    flags+=("--secret-access-key=")
    two_word_flags+=("--secret-access-key")
    local_nonpersistent_flags+=("--secret-access-key")
    local_nonpersistent_flags+=("--secret-access-key=")
    flags+=("--skip-validation")
    local_nonpersistent_flags+=("--skip-validation")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_flag+=("--access-key-id=")
    must_have_one_flag+=("--bucket=")
    must_have_one_flag+=("--endpoint=")
    must_have_one_flag+=("--region=")
    must_have_one_flag+=("--secret-access-key=")
    must_have_one_noun=()
    noun_aliases=()
}

_kots_velero_ensure-permissions()
{
    last_command="kots_velero_ensure-permissions"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--velero-namespace=")
    two_word_flags+=("--velero-namespace")
    local_nonpersistent_flags+=("--velero-namespace")
    local_nonpersistent_flags+=("--velero-namespace=")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_velero_print-fs-instructions()
{
    last_command="kots_velero_print-fs-instructions"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--kotsadm-namespace=")
    two_word_flags+=("--kotsadm-namespace")
    local_nonpersistent_flags+=("--kotsadm-namespace")
    local_nonpersistent_flags+=("--kotsadm-namespace=")
    flags+=("--kotsadm-registry=")
    two_word_flags+=("--kotsadm-registry")
    local_nonpersistent_flags+=("--kotsadm-registry")
    local_nonpersistent_flags+=("--kotsadm-registry=")
    flags+=("--registry-password=")
    two_word_flags+=("--registry-password")
    local_nonpersistent_flags+=("--registry-password")
    local_nonpersistent_flags+=("--registry-password=")
    flags+=("--registry-username=")
    two_word_flags+=("--registry-username")
    local_nonpersistent_flags+=("--registry-username")
    local_nonpersistent_flags+=("--registry-username=")
    flags+=("--with-minio")
    local_nonpersistent_flags+=("--with-minio")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_velero()
{
    last_command="kots_velero"

    command_aliases=()

    commands=()
    commands+=("configure-aws-s3")
    commands+=("configure-azure")
    commands+=("configure-gcp")
    commands+=("configure-hostpath")
    commands+=("configure-internal")
    commands+=("configure-nfs")
    commands+=("configure-other-s3")
    commands+=("ensure-permissions")
    commands+=("print-fs-instructions")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_version()
{
    last_command="kots_version"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kots_root_command()
{
    last_command="kots"

    command_aliases=()

    commands=()
    commands+=("admin-console")
    commands+=("backup")
    commands+=("completion")
    commands+=("docker")
    commands+=("download")
    commands+=("enable-ha")
    commands+=("get")
    commands+=("help")
    commands+=("install")
    commands+=("pull")
    commands+=("remove")
    commands+=("reset-password")
    commands+=("reset-tls")
    commands+=("restore")
    commands+=("set")
    commands+=("upload")
    commands+=("upstream")
    commands+=("velero")
    commands+=("version")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--as=")
    two_word_flags+=("--as")
    flags+=("--as-group=")
    two_word_flags+=("--as-group")
    flags+=("--as-uid=")
    two_word_flags+=("--as-uid")
    flags+=("--cache-dir=")
    two_word_flags+=("--cache-dir")
    flags+=("--certificate-authority=")
    two_word_flags+=("--certificate-authority")
    flags+=("--client-certificate=")
    two_word_flags+=("--client-certificate")
    flags+=("--client-key=")
    two_word_flags+=("--client-key")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    flags+=("--request-timeout=")
    two_word_flags+=("--request-timeout")
    flags+=("--server=")
    two_word_flags+=("--server")
    two_word_flags+=("-s")
    flags+=("--tls-server-name=")
    two_word_flags+=("--tls-server-name")
    flags+=("--token=")
    two_word_flags+=("--token")
    flags+=("--user=")
    two_word_flags+=("--user")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

__start_kots()
{
    local cur prev words cword split
    declare -A flaghash 2>/dev/null || :
    declare -A aliashash 2>/dev/null || :
    if declare -F _init_completion >/dev/null 2>&1; then
        _init_completion -s || return
    else
        __kots_init_completion -n "=" || return
    fi

    local c=0
    local flag_parsing_disabled=
    local flags=()
    local two_word_flags=()
    local local_nonpersistent_flags=()
    local flags_with_completion=()
    local flags_completion=()
    local commands=("kots")
    local command_aliases=()
    local must_have_one_flag=()
    local must_have_one_noun=()
    local has_completion_function=""
    local last_command=""
    local nouns=()
    local noun_aliases=()

    __kots_handle_word
}

if [[ $(type -t compopt) = "builtin" ]]; then
    complete -o default -F __start_kots kots
else
    complete -o default -o nospace -F __start_kots kots
fi

# ex: ts=4 sw=4 et filetype=sh
