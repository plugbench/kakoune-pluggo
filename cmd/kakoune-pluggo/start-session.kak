declare-option -hidden str pluggo_last_yank_client %val{client}
declare-option -hidden str pluggo_bin '{{.PluggoBin}}'

hook -group pluggo global RegisterModified '"' %{
    set-option global pluggo_last_yank_client %val{client}
    evaluate-commands %sh{
        NATS_TOKEN='{{.Nats.Token}}' "$kak_opt_pluggo_bin" command cmd.put.clipboard "$kak_main_reg_dquote"
    }
}

# Files shown are visits, for the frecency store, as file URLs like the plumber's.
hook -group pluggo global WinDisplay .* %{
    nop %sh{
        [ -f "$kak_buffile" ] || exit 0
        NATS_TOKEN='{{.Nats.Token}}' "$kak_opt_pluggo_bin" command cmd.add.frecent "file://$(uname -n)$kak_buffile" </dev/null >/dev/null 2>&1 &
    }
}

evaluate-commands %sh{
    NATS_TOKEN='{{.Nats.Token}}' "$kak_opt_pluggo_bin" daemon "$kak_session" </dev/null >/dev/null 2>&1 &
    daemon_pid=$!
    printf 'declare-option -hidden str pluggo_daemon_pid "%s"\n' "$daemon_pid"
    NATS_TOKEN='{{.Nats.Token}}' "$kak_opt_pluggo_bin" event "event.logged.kakoune-pluggo.info" "pid for session $kak_session is $daemon_pid"
}

hook -group pluggo global KakEnd .* %{
    nop %sh{ kill -HUP "$kak_opt_pluggo_daemon_pid" >/dev/null 2>&1 }
}

define-command \
    -override \
    -hidden \
    -params 1 \
    pluggo-clip %{
    evaluate-commands -try-client %opt{pluggo_last_yank_client} %{
        evaluate-commands %sh{
            NATS_TOKEN='{{.Nats.Token}}' "$kak_opt_pluggo_bin" event 'event.logged.kakoune-pluggo.debug' "setting from '$kak_main_reg_dquote' to '$1'" 2>/dev/null
            if [ "$1" = "$kak_main_reg_dquote" ]; then
                NATS_TOKEN='{{.Nats.Token}}' "$kak_opt_pluggo_bin" event 'event.logged.kakoune-pluggo.debug' "skipping update" 2>/dev/null
                exit 0
            fi
            printf "set-register dquote '"
            printf %s "$1" |sed -e "s/'/''/g"
            printf "'\n"
        }
    }
}

define-command \
    -override \
    -hidden \
    -params 4 \
    -docstring %{pluggo-open <client> <filename> <selection> <fixupkeys>} \
    pluggo-open %{
    evaluate-commands -try-client "%arg{1}" %{
        try %{
            edit -existing "%arg{2}"
            select -codepoint "%arg{3}"
            execute-keys "%arg{4}"
            try focus
        } catch %{
            echo -markup "{Error}%val{error}"
            echo -debug "%val{error}"
        }
    }
}

define-command -override -hidden -params 3 pluggo-show-text %{
    evaluate-commands -save-regs t -try-client "%arg{1}" %{
        try %{
            evaluate-commands %sh{
                have_show=false
                next_n=0
                eval set -- "$kak_quoted_buflist"
                for buf in "$@"; do
                    case "$buf" in
                    "*show*")
                        have_show=true
                        ;;
                    "*show-"*"*")
                        n_part=${buf%"*"}
                        n_part=${n_part#"*"show-}
                        next_n=$(( n_part >= next_n ? n_part + 1 : next_n ))
                        ;;
                    esac
                done
                if [ "$have_show" = false ]; then
                    printf 'edit -scratch *show*\n'
                else
                    printf 'edit -scratch *show-%d*\n' "$next_n"
                fi
            }
            set-register t "%arg{2}"
            set-option buffer plumb_wdir "%arg{3}"
            execute-keys '%"tRgk'
            try focus
        } catch %{
            echo -markup "{Error}%val{error}"
            echo -debug "%val{error}"
        }
    }
}

declare-option -docstring 'a directory to send instead of $(pwd) for wdir' str plumb_wdir

define-command \
    -params 1.. \
    -docstring %{plumb [<switches>] <text>: send text to the plumber
Switches:
    -attr <name>=<value>   Add an attribute to the message (accumulative)} \
    plumb %{
    evaluate-commands %sh{
        attrs="session=${kak_session}"
        while [ $# -ne 1 ]; do
            case "$1" in
                -attr)
                    attrs="${attrs} $2"
                    shift
                    ;;
                *)
                    printf 'fail "unknown switch %s"\n' "$1"
                    exit 0
            esac
            shift
        done
        wdir="$kak_opt_plumb_wdir"
        if [ -z "$wdir" ]; then
            wdir="$(pwd)"
        fi
        err="$(9 plumb -s kakoune -w "${wdir}" -a "${attrs}" "$@" 2>&1)"
        if [ -n "$err" ]; then
            printf 'fail "%s"\n' "$err"
        fi
    }
}

define-command -hidden plumb-click-WORD %{
    execute-keys 'Z[<a-w>"lyz<a-i><a-w>'
    plumb -attr %sh{
        eval set -- "$kak_reg_l"
        printf click=%d $((${#1} - 1))
    } %val{selection}
}

declare-option -hidden str plumb_diff_filename
declare-option -hidden int plumb_diff_chunk_start
declare-option -hidden str-list plumb_diff_preceding_adds

define-command -hidden plumb-click-diff %{
    try %{
        evaluate-commands -draft %{
            execute-keys <a-/>^diff<space>[^\n]+<space>b/([^\n]+)$<ret>
            set-option global plumb_diff_filename %reg{1}
        }
        evaluate-commands -draft %{
            execute-keys '<a-/>^@@ -\d+,\d+ \+(\d+),\d+ @@<ret>'
            set-option global plumb_diff_chunk_start %reg{1}
        }
        evaluate-commands -draft %{
            execute-keys '<a-?>^@@ <ret>J<a-s>gh<a-K>-<ret>"ay'
            set-option global plumb_diff_preceding_adds %reg{a}
        }
        evaluate-commands %sh{
            eval set -- "$kak_quoted_opt_plumb_diff_preceding_adds"
            line=$(( $kak_opt_plumb_diff_chunk_start + $# - 1 ))
            column=$(( $kak_cursor_column - 1 ))
            text="${kak_opt_plumb_diff_filename}:${line}:${column}"
            printf 'plumb "%s"\n' "$text"
        }
    } catch %{
        # Fallback case, which means we are likely in a commit header and
        # can't find a diff and chunk begin line above us, so do the usual
        # thing.
        plumb-click-WORD
    }
}

define-command \
    -docstring %{plumb-click: send selection or WORD to plumber

If the selection length is 1, send the current WORD to the plumber along with
click coordinates.  Otherwise, send the selection to the plumber.

There is special handling for filetype=diff.} \
    plumb-click %{
    evaluate-commands -itersel -draft %{
        # Move forward if on a single whitespace
        try %{ execute-keys '<a-k>\A\s\z<ret>/[^\s]<ret>' }
        try %{
            # If we have more than a single character, send it as an
            # intentional selection
            execute-keys '<a-K>\A[^\s]\z<ret>'
            plumb %val{selection}
        } catch %{
            evaluate-commands -draft %sh{
                case "$kak_opt_filetype" in
                    diff) printf plumb-click-diff\\n ;;
                    *)    printf plumb-click-WORD\\n ;;
                esac
            }
        }
    }
}

map global normal <ret> ': plumb-click<ret>'
