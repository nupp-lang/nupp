# Selects the interpreter Nupp runs on. Sourced rather than run, because the
# answer is delivered by putting a directory on PATH: the choice has to reach
# the processes the toolchain starts, and comptime workers, `nupp run`, the LSP
# relay and the test runner all spell it `luajit`.

# Generated Nupp is written in the LuaJIT 3.0 syntax that 2.1 backported, and
# every Nupp command either produces generated code or runs it, so an older
# interpreter cannot do the job whatever it manages to load.
LUAJIT_FLOOR=1784535649

luajit_is_usable() {
    command -v luajit >/dev/null 2>&1 || return 1
    reported=$(luajit -v 2>/dev/null | sed -n '1s/^LuaJIT \([0-9.]*\).*/\1/p')
    # Only the 2.1 series needs the rolling number looked at: 2.0 and older
    # never had the extensions, and anything past 2.1 was born with them.
    case "$reported" in
        "")             return 0 ;; # an unreadable banner proves nothing
        2.1.*)          [ "${reported#2.1.}" -ge "$LUAJIT_FLOOR" ] 2>/dev/null \
                            && return 0 ;;
        1.*|2.0*|2.1)   return 1 ;;
        *)              return 0 ;;
    esac
    return 1
}

# A staged interpreter may remain usable when a child changes its AOT compiler.
# Match both the patch and executable to the receipt written by our build, so a
# version banner or an unrelated PATH interpreter cannot claim the fix.
luajit_has_required_patch() {
    patch_interpreter=$(command -v luajit) || return 1
    [ -f "$patch_interpreter" ] || return 1
    patch_prefix=$(CDPATH= cd -- "$(dirname "$patch_interpreter")/.." && pwd) || return 1
    [ -f "$patch_prefix/.nupp-runtime-patch" ] || return 1
    [ -f "$1/scripts/patches/luajit-irt-size.patch" ] || return 1
    patch_receipt=$(
        cksum < "$1/scripts/patches/luajit-irt-size.patch"
        cksum < "$patch_interpreter"
    ) || return 1
    [ "$(cat "$patch_prefix/.nupp-runtime-patch")" = "$patch_receipt" ]
}

# ARM64 needs the pinned build's IR type-width fix: a new banner alone does not
# establish correct FFI argument widths. Other architectures retain a usable
# PATH interpreter; otherwise provision the pinned build automatically.
select_luajit() {
    case "$(uname -m 2>/dev/null)" in
        arm64|aarch64) luajit_has_required_patch "$1" && luajit_is_usable && return 0 ;;
        *) luajit_is_usable && return 0 ;;
    esac
    staged=$("$1/scripts/toolchain" luajit) || {
        echo "nupp: scripts/toolchain could not provision the required LuaJIT" >&2
        return 1
    }
    # Toolchain answers use drive-letter paths because native Windows programs
    # consume them directly. PATH is still assembled by the MSYS shell, where
    # that drive colon is a separator, so convert this one use back to a mount
    # path before prepending it.
    staged_path=$staged
    case "$(uname -s 2>/dev/null)" in
        MINGW*|MSYS*|CYGWIN*) staged_path=$(cygpath -u "$staged") || return 1 ;;
    esac
    PATH="$staged_path/bin:$PATH"
    export PATH
    [ -x "$staged_path/bin/luajit" ] && luajit_is_usable || {
        echo "nupp: LuaJIT staged at $staged does not run" >&2
        return 1
    }
    return 0
}
