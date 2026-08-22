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

# Uses whatever is on PATH when it is new enough, and otherwise builds the pinned
# LuaJIT and puts that on PATH instead. Telling somebody to go and install an
# interpreter new enough to parse what this compiler emits is asking them to
# solve a problem this can solve.
select_luajit() {
    luajit_is_usable && return 0
    staged=$("$1/scripts/toolchain" luajit) || {
        echo "nupp: no LuaJIT new enough for generated Nupp is on PATH, and" \
            "scripts/toolchain could not build the pinned one" >&2
        return 1
    }
    PATH="$staged/bin:$PATH"
    export PATH
    luajit_is_usable || {
        echo "nupp: LuaJIT staged at $staged does not run" >&2
        return 1
    }
    return 0
}
