#!/bin/sh
# Generates pass.nupp: the template with the columnar part over {integer}
# and over {int32}. Run `nupp fmt --write pass.nupp` after.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
part() {
    sed -e "s/@SFX@/$1/g" -e "s/@COL@/$2/g" -e "s/@W@/$3/g" "$HERE/columnar.part.nupp.in"
}
{
    sed -n '1,/^-- @COLUMNAR@$/p' "$HERE/pass.template.nupp.in" | sed '$d'
    part "" "{integer}" ""
    echo
    part "32" "{int32}" "math.i32.wrap"
    sed -n '/^-- @COLUMNAR@$/,$p' "$HERE/pass.template.nupp.in" | sed '1d'
} > "$HERE/pass.nupp"
